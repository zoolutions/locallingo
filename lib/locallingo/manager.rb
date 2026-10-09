# frozen_string_literal: true

require "yaml"
require "json"
require "logger"
require "fileutils"

require_relative "configuration"
require_relative "key_flattener"
require_relative "state_store"
require_relative "providers/ruby_llm"
require_relative "batch_translator"
require_relative "validators/missing"
require_relative "validators/outdated"
require_relative "validators/duplicate_values"
require_relative "validators/manual_edits"

module Locallingo
  # Manages translations with source-hash change detection.
  #
  # - Tracks source hashes to detect changes (drift)
  # - Only translates missing/changed keys
  # - Validates translation completeness (config-selected validators)
  # - Merges LLM output back into the flat `<namespace>.<locale>.yml` files
  #
  # Everything app-specific (locales, provider/model, prompt context/glossary,
  # per-language guides, which validators run) comes from the Configuration.
  class Manager
    MAX_RETRIES = BatchTranslator::MAX_RETRIES
    MAX_MISSING_RETRIES = BatchTranslator::MAX_MISSING_RETRIES
    BASE_SLEEP_DURATION = BatchTranslator::BASE_SLEEP_DURATION

    attr_reader :config, :dry_run, :verbose, :logger, :cli_name

    def initialize(config: nil, root_path: nil, package: nil,
                   dry_run: false, verbose: false, logger: nil, cli_name: "lingo")
      @config = config || Configuration.load(root_path: root_path || Dir.pwd, package:)
      @dry_run = dry_run
      @verbose = verbose
      @cli_name = cli_name
      @state = StateStore.new(@config.state_dir)
      @provider = Providers::RubyLLM.new(provider: @config.provider)
      @logger = logger || build_logger
    end

    # Current translation status per target locale.
    def status
      source = load_source_translations

      config.target_locales.each_with_object({}) do |locale, results|
        target = load_locale_translations(locale)
        locale_state = @state.load(locale)
        missing = source.keys - target.keys
        outdated = outdated_validator.outdated_keys(source, locale_state)

        results[locale] = {
          total_keys: source.keys.size,
          translated: target.keys.size,
          missing: missing.size,
          outdated: outdated.size,
          missing_keys: missing.first(10),
          outdated_keys: outdated.first(10)
        }
      end
    end

    # Validate translations; returns an array of violation hashes. Which checks
    # run is config-driven.
    def validate
      violations = []
      source = load_source_translations

      violations.concat(Validators::DuplicateValues.new.call(source:)) if config.validator_enabled?(:duplicate_values)

      config.target_locales.each do |locale|
        target = load_locale_translations(locale)
        locale_state = @state.load(locale)

        violations.concat(missing_validator.call(source:, target:, locale:)) if config.validator_enabled?(:missing)
        if config.validator_enabled?(:outdated)
          violations.concat(outdated_validator.call(source:, locale_state:, locale:))
        end
        if config.validator_enabled?(:manual_edits)
          violations.concat(Validators::ManualEdits.new(cli_name:).call(target:, locale_state:, locale:))
        end
      end

      violations
    end

    # Translate missing/changed keys for one or all target locales. Returns
    # `{ locale => failed_keys }`; keys that failed are not written.
    def translate!(locale: nil, force: false, force_keys: [])
      @provider.ensure_credentials!

      locales_to_process = locale ? [locale] : config.target_locales
      source = load_source_translations

      locales_to_process.to_h do |target_locale|
        [target_locale, translate_locale(source, target_locale, force:, force_keys:)]
      end
    end

    # Mark hand-edited target values as intentional (source_hash + target_hash +
    # manual flag) so the manual-edits validator stops flagging them and
    # translate won't overwrite them. Unscoped, it accepts exactly the keys the
    # manual-edits validator flags; `keys:` accepts the named keys regardless of
    # drift; `all: true` marks every translated key (initial adoption). Returns
    # `{ locale => accepted_keys }`.
    def accept_edits!(locale: nil, keys: [], all: false)
      source = load_source_translations
      locales = locale ? [locale] : config.target_locales

      plans = locales.map do |target_locale|
        target = load_locale_translations(target_locale)
        locale_state = @state.load(target_locale)
        accepted = keys_to_accept(source, target, locale_state, keys:, all:)
        [target_locale, target, locale_state, accepted]
      end

      ensure_keys_matched!(keys, plans)

      plans.each_with_object({}) do |(target_locale, target, locale_state, accepted), results|
        accepted.each do |key|
          locale_state[key] = {
            "source_hash" => @state.hash(source[key]),
            "target_hash" => @state.hash(target[key]),
            "manual" => true
          }
        end
        @state.save(target_locale, locale_state) unless dry_run
        results[target_locale] = accepted
      end
    end

    # CRC32 hash of the current source translations (change-detection fingerprint).
    def source_hash
      format("%08x", Zlib.crc32(load_source_translations.to_json))
    end

    # Refresh source hashes from the current translation files, backfill a
    # `target_hash` baseline for entries that lack one, and prune state for
    # keys that no longer exist. An existing `target_hash` and the `manual`
    # flag are never touched — hand-edit protection is never dropped by a
    # sync; use `accept_edits!` to resolve hand-edit drift explicitly.
    # Returns the combined state.
    def sync_state!
      source = load_source_translations

      en_state = @state.load(config.source_locale)
      source.each { |key, value| en_state[key] = { "source_hash" => @state.hash(value) } }
      en_state.each_key { |key| en_state.delete(key) unless source.key?(key) }
      @state.save(config.source_locale, en_state) unless dry_run

      config.target_locales.each { |locale| sync_locale_state(source, locale) }

      combined = { config.source_locale => @state.load(config.source_locale) }
      config.target_locales.each { |locale| combined[locale] = @state.load(locale) }
      combined
    end

    # Run the configured after_translate hook commands (from the app root).
    def run_after_translate_hooks
      config.after_translate.each do |command|
        log("Running: #{command}")
        Dir.chdir(config.root_path) { system(command) }
      end
    end

    private

    def missing_validator = @missing_validator ||= Validators::Missing.new(cli_name:)
    def outdated_validator = @outdated_validator ||= Validators::Outdated.new(cli_name:)

    def batch_translator
      @batch_translator ||= BatchTranslator.new(
        provider: @provider, model: config.translate_model, batch_size: config.batch_size, log: method(:log)
      )
    end

    def sync_locale_state(source, locale)
      target = load_locale_translations(locale)
      locale_state = @state.load(locale)

      target.each do |key, value|
        next unless source[key]

        existing = locale_state[key]
        entry = existing.is_a?(Hash) ? existing.dup : {}
        entry["source_hash"] = @state.hash(source[key])
        # Backfill a baseline for hand-added translations so the manual-edits
        # validator can watch them; an existing target_hash is never recomputed —
        # that would silently absorb hand-edit drift.
        entry["target_hash"] ||= @state.hash(value)
        locale_state[key] = entry
      end
      locale_state.each_key { |key| locale_state.delete(key) unless target.key?(key) }
      @state.save(locale, locale_state) unless dry_run
    end

    def keys_to_accept(source, target, locale_state, keys:, all:)
      return keys.select { |key| source.key?(key) && target.key?(key) } if keys.any?
      return target.keys.select { |key| source.key?(key) } if all

      target.keys.select do |key|
        entry = locale_state[key]
        next false unless source.key?(key) && entry.is_a?(Hash) && !entry["manual"]

        entry["target_hash"] && entry["target_hash"] != @state.hash(target[key])
      end
    end

    def ensure_keys_matched!(keys, plans)
      return if keys.empty?

      matched = plans.flat_map { |_, _, _, accepted| accepted }
      missing = keys - matched
      return if missing.empty?

      raise Error, "accept-edits: key(s) not found in any target locale: #{missing.join(", ")}"
    end

    def translate_locale(source, target_locale, force:, force_keys:)
      log("Processing #{target_locale}...")

      target = load_locale_translations(target_locale)
      locale_state = @state.load(target_locale)
      exceptions = load_exceptions(target_locale)

      keys = determine_keys_to_translate(source, target, locale_state, force:, force_keys:, exceptions:)
      if keys.empty?
        log("  No keys to translate for #{target_locale}")
        return []
      end

      log("  Translating #{keys.size} keys...")
      translated, failed = batch_translator.call(source, keys, instructions: translation_prompt(target_locale))

      successful = translated.except(*failed)
      unless dry_run
        merge_translations(target_locale, successful)
        update_locale_state(source, locale_state, successful)
        @state.save(target_locale, locale_state)
      end

      log("  Completed #{target_locale}: #{successful.size} translated, #{failed.size} failed")
      failed
    end

    def translation_prompt(locale)
      language = config.language_name(locale)
      <<~PROMPT
        Translate the following texts from #{config.language_name(config.source_locale)} into natural, idiomatic #{language}.
        This is for #{config.context}.

        ## Idiomatic Translation
        - Translate the meaning, not word for word: write what a native #{language} speaker would actually say in this situation
        - Use the phrasing, word order and UI conventions that are standard in #{language} software, even when they differ from the source
        - Replace source-language idioms and set phrases with their natural #{language} equivalent instead of translating them literally
        - Avoid calques and anglicisms when an established #{language} expression exists
        - Never add, drop or change information to make a sentence sound natural

        ## General Rules
        - Preserve placeholders like #{config.placeholder_style} exactly as they appear
        - Preserve HTML tags if present
        - Use formal business language
        - Keep translations concise - UI space is limited
        - Escape every double quote (") inside a translated value as \\" so the reply stays valid JSON
        - Keep typographic quotes (“ ” „ ‚ « ») exactly as they appear in the source
        #{glossary_section}#{language_guide_section(locale)}
        Return ONLY a raw JSON object mapping each input key to its translation,
        with no surrounding prose and no markdown code fences:
        {"key1": "translated1", "key2": "translated2"}
      PROMPT
    end

    def glossary_section
      return "" if config.glossary.empty?

      lines = config.glossary.map { |term, meaning| "        - \"#{term}\" = #{meaning}" }
      "\n## Terminology\n#{lines.join("\n")}\n"
    end

    def language_guide_section(locale)
      guide = config.language_guide(locale)
      guide.empty? ? "" : "\n#{guide}\n"
    end

    def determine_keys_to_translate(source, target, locale_state, force:, force_keys:, exceptions:)
      manual_keys = locale_state.select { |_k, v| v.is_a?(Hash) && v["manual"] }.keys.to_set
      return source.keys - manual_keys.to_a if force
      return force_keys & source.keys if force_keys.any?

      excluded = exceptions.keys.to_set | manual_keys
      missing = source.keys - target.keys - excluded.to_a
      outdated = outdated_validator.outdated_keys(source, locale_state) - excluded.to_a
      (missing + outdated).uniq
    end

    def update_locale_state(source, locale_state, translations)
      translations.each_key do |key|
        next unless source[key]

        existing = locale_state[key]
        entry = {
          "source_hash" => @state.hash(source[key]),
          "target_hash" => @state.hash(translations[key])
        }
        # A force-keyed retranslation may overwrite a manual value on explicit
        # request, but the protection flag itself must survive.
        entry["manual"] = true if existing.is_a?(Hash) && existing["manual"]
        locale_state[key] = entry
      end
    end

    def merge_translations(locale, translations)
      translations.group_by { |key, _| key.split(".").first }.each do |namespace, pairs|
        file_path = find_or_create_locale_file(locale, namespace)
        existing = File.exist?(file_path) ? YAML.load_file(file_path) : {}
        existing[locale] ||= {}
        pairs.each { |key, value| KeyFlattener.set_nested_value(existing[locale], key, value) }
        File.write(file_path, existing.to_yaml)
      end
    end

    def find_or_create_locale_file(locale, namespace)
      pattern = File.join(config.locales_dir, "**", "#{namespace}.#{locale}.yml")
      Dir.glob(pattern).min || File.join(config.locales_dir, "#{namespace}.#{locale}.yml")
    end

    def load_source_translations = load_locale_translations(config.source_locale)

    def load_locale_translations(locale)
      translations = {}
      patterns = [
        File.join(config.locales_dir, "**", "*.#{locale}.yml"),
        File.join(config.locales_dir, "#{locale}.yml")
      ]

      patterns.each do |pattern|
        Dir.glob(pattern).each do |file|
          content = YAML.load_file(file)
          next unless content.is_a?(Hash) && content[locale]

          KeyFlattener.flatten(content[locale]).each do |key, value|
            translations[key] = value if value.is_a?(String)
          end
        end
      end

      translations
    end

    def load_exceptions(locale)
      exception_file = File.join(config.exceptions_dir, "#{locale}.yml")
      return {} unless File.exist?(exception_file)

      content = YAML.load_file(exception_file)
      return {} unless content.is_a?(Hash) && content[locale]

      KeyFlattener.flatten(content[locale])
    rescue StandardError => e
      log("  Failed to load exceptions for #{locale}: #{e.message}", level: :warn)
      {}
    end

    def build_logger
      FileUtils.mkdir_p(config.state_dir)
      logger = Logger.new(config.log_file, 5, 1_048_576)
      logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity}: #{msg}\n"
      end
      logger
    end

    def log(message, level: :info)
      logger&.public_send(level, message)
      warn(message) if verbose
    end
  end
end
