# frozen_string_literal: true

require "yaml"

require_relative "configuration"
require_relative "key_flattener"
require_relative "providers/ruby_llm"
require_relative "quality/static_rules"
require_relative "quality/british_spellings"
require_relative "quality/terminology"

module Locallingo
  # Checks translation quality and suggests improvements.
  #
  # Static (provider-free) checks: regex rules, universal fixes, terminology,
  # optional British-spelling drift, and a very-long-text heuristic. An optional
  # AI pass (RubyLLM) reviews a sample for clarity/professionalism.
  #
  # `fix!` rewrites the auto-fixable suggestions (universal fixes + British
  # spellings) back into the locale files, preserving case.
  class QualityChecker
    LONG_TEXT_THRESHOLD = 200

    attr_reader :config, :verbose, :logger

    def initialize(config: nil, root_path: nil, package: nil, verbose: false, logger: nil)
      @config = config || Configuration.load(root_path: root_path || Dir.pwd, package:)
      @verbose = verbose
      @logger = logger
      @provider = Providers::RubyLLM.new(provider: @config.provider)
      @terminology = Quality::Terminology.new(@config.terminology_setting, base_path: @config.base_path)
    end

    # Check the translations for a locale: all of them, those under +prefix+
    # (e.g. "yoga."), or exactly the named +keys+. The AI pass reviews a sample
    # of up to `quality.sample_size` keys, or every named key.
    def check(locale: nil, use_ai: false, prefix: nil, keys: nil)
      locale ||= config.source_locale
      translations = scoped_translations(locale, prefix:, keys:)

      suggestions = translations.flat_map { |key, text| check_text(key, text, locale) }
      suggestions.concat(keys ? suggest_improvements(translations, locale) : ai_sample(translations, locale)) if use_ai
      suggestions
    end

    # Check a single key.
    def check_key(key, locale, use_ai: false)
      translations = load_locale_translations(locale)
      text = translations[key]
      return [{ key:, error: "Key not found" }] unless text

      suggestions = check_text(key, text, locale)
      suggestions.concat(suggest_improvements({ key => text }, locale)) if use_ai
      suggestions
    end

    # Auto-fix the fixable suggestions in the locale files. Returns
    # { fixed: <file count>, skipped: <non-fixable count> }.
    def fix!(locale: nil, dry_run: false)
      locale ||= config.source_locale
      suggestions = check(locale:)
      fixable = suggestions.select { |s| s[:fix] }
      return { fixed: 0, skipped: suggestions.size - fixable.size } if fixable.empty?

      changed = apply_fixes(locale, fixable)

      changed.each { |file, content| File.write(file, content) } unless dry_run
      changed.each_key { |file| log("#{dry_run ? "Would fix" : "Fixed"}: #{file}") }

      { fixed: changed.size, skipped: suggestions.size - fixable.size }
    end

    # AI suggestions for a batch of key=>text pairs.
    def suggest_improvements(keys_with_text, locale)
      unless @provider.credentials?
        warn "⚠️  No LLM credentials — skipping AI suggestions"
        return []
      end

      result = @provider.chat(
        model: config.quality_model,
        instructions: quality_prompt(locale),
        payload: keys_with_text
      )

      result.map do |key, suggestion|
        symbolized = suggestion.transform_keys(&:to_sym)
        symbolized[:severity] = symbolized[:severity]&.to_sym || :info
        { key:, text: keys_with_text[key], locale:, source: :ai, **symbolized }
      end
    rescue StandardError => e
      warn "⚠️  AI suggestion failed: #{e.message}"
      []
    end

    private

    def check_text(key, text, locale)
      suggestions = []
      suggestions.concat(Quality::StaticRules.universal_fixes(key, text, locale))
      suggestions.concat(Quality::StaticRules.check(key, text, locale))
      suggestions.concat(@terminology.check(key, text, locale))
      suggestions.concat(Quality::BritishSpellings.check(key, text, locale)) if british_spellings_for?(locale)
      suggestions << long_text_suggestion(key, text, locale) if text.length > LONG_TEXT_THRESHOLD
      suggestions.compact
    end

    def british_spellings_for?(locale)
      config.british_spellings? && locale.to_s == config.source_locale.to_s
    end

    def long_text_suggestion(key, text, locale)
      {
        key:, text: truncate(text, 100), locale:,
        category: :length,
        issue: "Text is very long (#{text.length} chars) - consider splitting",
        severity: :info, source: :static
      }
    end

    def scoped_translations(locale, prefix:, keys:)
      translations = load_locale_translations(locale)
      return slice_keys(translations, keys, locale) if keys
      return translations unless prefix

      scoped = translations.select { |key, _| key.start_with?(prefix) }
      raise Error, "No keys match prefix #{prefix.inspect} in #{locale}" if scoped.empty?

      scoped
    end

    def slice_keys(translations, keys, locale)
      missing = keys - translations.keys
      raise Error, "quality: key(s) not found in #{locale}: #{missing.join(", ")}" if missing.any?

      translations.slice(*keys)
    end

    def ai_sample(translations, locale)
      sample_size = [translations.size, config.quality_sample_size].min
      sample = translations.to_a.sample(sample_size).to_h
      suggest_improvements(sample, locale)
    end

    def apply_fixes(locale, fixable)
      changed = {}
      Dir.glob(File.join(config.locales_dir, "**", "*.#{locale}.yml")).each do |file|
        original = File.read(file)
        content = original.dup

        fixable.each do |suggestion|
          next unless content.include?(suggestion[:text])

          fixed_text = apply_case_preserving_fix(suggestion[:text], suggestion[:fix])
          content = content.gsub(suggestion[:text], fixed_text)
        end

        changed[file] = content if content != original
      end
      changed
    end

    def apply_case_preserving_fix(text, fix)
      text.gsub(/\b#{Regexp.escape(fix[:from])}\b/i) do |match|
        if match == match.upcase then fix[:to].upcase
        elsif match[0] == match[0].upcase then fix[:to].capitalize
        else fix[:to]
        end
      end
    end

    def quality_prompt(locale)
      <<~PROMPT
        Review these UI translations for #{config.context}.
        Suggest improvements for clarity, professionalism, and user-friendliness.
        #{glossary_section}#{language_guide_section(locale)}
        For each translation that needs improvement, provide:
        1. The issue (brief)
        2. Suggested improvement
        3. Severity: "error" (must fix), "warning" (should fix), "info" (nice to have)

        Only include translations that actually need changes.
        Return ONLY a raw JSON object, with no surrounding prose and no markdown
        code fences: {"key": {"issue": "...", "suggestion": "...", "severity": "..."}}

        Locale: #{locale}
      PROMPT
    end

    def glossary_section
      return "" if config.glossary.empty?

      lines = config.glossary.map { |term, meaning| "        - \"#{term}\" = #{meaning}" }
      "\n#{config.context} terminology:\n#{lines.join("\n")}\n"
    end

    def language_guide_section(locale)
      guide = config.language_guide(locale)
      guide.empty? ? "" : "\n#{guide}\n"
    end

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

    def truncate(text, length)
      text.length > length ? "#{text[0, length]}..." : text
    end

    def log(message)
      logger&.info(message)
      warn(message) if verbose
    end
  end
end
