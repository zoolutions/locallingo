# frozen_string_literal: true

require "yaml"
require "erb"

module Locallingo
  # Loads and resolves `.locallingo.yml`.
  #
  # The file has a `defaults:` block that applies to the whole app, plus an
  # optional `packages:` list. Each package entry deep-merges onto `defaults`,
  # so a package only lists the keys it changes. With no `packages:` (the common
  # case), the resolved config is just `defaults` merged over the shipped
  # `config/locallingo.default.yml`.
  #
  # Typed readers expose everything the Manager/QualityChecker/CLI need, so no
  # other class parses raw config hashes.
  class Configuration
    CONFIG_FILENAMES = %w[.locallingo.yml .locallingo.yaml].freeze
    DEFAULT_CONFIG_PATH = File.expand_path("../../config/locallingo.default.yml", __dir__)

    attr_reader :root_path, :package, :data

    # Resolve config for +root_path+, optionally scoped to a +package+ path from
    # the `packages:` list.
    def self.load(root_path: Dir.pwd, package: nil)
      new(root_path:, package:)
    end

    def initialize(root_path: Dir.pwd, package: nil, data: nil)
      @root_path = File.expand_path(root_path)
      @package = package
      @data = data || resolve
    end

    # --- locations -----------------------------------------------------------

    # The directory config paths resolve against — the package path when scoped,
    # else the app root.
    def base_path
      package ? File.join(root_path, package) : root_path
    end

    def source_locale = data.fetch("source_locale")
    def target_locales = Array(data.fetch("target_locales"))
    def all_locales = [source_locale, *target_locales].uniq

    def locales_dir = File.join(base_path, data.fetch("locales_dir"))
    def state_dir = File.join(base_path, data.fetch("state_dir"))
    def exceptions_dir = File.join(state_dir, "exceptions")
    def log_file = File.join(state_dir, "translation.log")

    # --- provider / models ---------------------------------------------------

    def provider = data.fetch("provider").to_sym
    def translate_model = dig("translate", "model")
    def batch_size = dig("translate", "batch_size")
    def quality_model = dig("quality", "model")
    def quality_sample_size = dig("quality", "sample_size")
    def british_spellings? = !!dig("quality", "british_spellings")
    def terminology_setting = dig("quality", "terminology")

    # --- prompt scaffolding --------------------------------------------------

    def context = data.fetch("context", "a business application")
    def placeholder_style = data.fetch("placeholder_style", "%<name>s, %<count>s")
    def glossary = data.fetch("glossary", {}) || {}

    # Extra per-locale style text appended to the translation prompt. A value of
    # `{ "file" => path }` is read from disk (relative to base_path); a String is
    # used verbatim. Returns "" when none is configured.
    def language_guide(locale)
      guide = (data.fetch("language_guides", {}) || {})[locale.to_s]
      return "" if guide.nil?
      return guide.to_s unless guide.is_a?(Hash) && guide["file"]

      path = File.expand_path(guide["file"], base_path)
      File.exist?(path) ? File.read(path) : ""
    end

    # Human-readable language name for a locale, from the guide config or a small
    # built-in map, falling back to the locale code itself.
    def language_name(locale)
      BUILTIN_LANGUAGE_NAMES[locale.to_s] || locale.to_s
    end

    # --- validators / strictness ---------------------------------------------

    def validator_enabled?(name)
      !!dig("validators", name.to_s)
    end

    # Violation types (symbols) a strict tier fails on. +tier+ is :strict or
    # :strict_all.
    def strict_types(tier)
      Array(dig("strict", tier.to_s)).map(&:to_sym)
    end

    # --- hooks ---------------------------------------------------------------

    def after_translate = Array(data.fetch("after_translate", []))

    BUILTIN_LANGUAGE_NAMES = {
      "de" => "German", "sv" => "Swedish", "fr" => "French",
      "af" => "Afrikaans", "es" => "Spanish", "it" => "Italian",
      "nl" => "Dutch", "pt" => "Portuguese", "da" => "Danish",
      "nb" => "Norwegian", "no" => "Norwegian", "fi" => "Finnish"
    }.freeze

    private

    def dig(*keys) = data.dig(*keys)

    # Merge: shipped defaults <- user `defaults:` <- selected `packages:` entry.
    def resolve
      merged = deep_merge(shipped_defaults, user_defaults)
      merged = deep_merge(merged, package_overrides) if package
      merged
    end

    def shipped_defaults
      load_yaml(DEFAULT_CONFIG_PATH).fetch("defaults", {})
    end

    def user_defaults
      file = config_file
      return {} unless file

      load_yaml(file).fetch("defaults", {}) || {}
    end

    def package_overrides
      file = config_file
      return {} unless file

      packages = load_yaml(file).fetch("packages", []) || []
      entry = packages.find { |p| p["path"] == package }
      raise Error, "No package #{package.inspect} in #{file}" unless entry

      entry.except("path")
    end

    def config_file
      CONFIG_FILENAMES
        .map { |name| File.join(root_path, name) }
        .find { |path| File.exist?(path) }
    end

    def load_yaml(path)
      YAML.safe_load(ERB.new(File.read(path)).result, aliases: true) || {}
    end

    def deep_merge(base, override)
      base.merge(override) do |_key, base_val, override_val|
        if base_val.is_a?(Hash) && override_val.is_a?(Hash)
          deep_merge(base_val, override_val)
        else
          override_val
        end
      end
    end
  end
end
