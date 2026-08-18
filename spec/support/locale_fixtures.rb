# frozen_string_literal: true

require "yaml"
require "json"
require "fileutils"

# Builds a throwaway app directory (config/locales + .locallingo.yml) in a tmp
# dir so specs exercise the real file IO without touching a real repo.
module LocaleFixtures
  # Yields a root path with the given locale files and config written.
  #
  #   with_app(
  #     config: { "target_locales" => ["de"] },
  #     locales: { "en" => { "greeting" => { "hi" => "Hello" } },
  #               "de" => { "greeting" => { "hi" => "Hallo" } } }
  #   ) { |root| ... }
  def with_app(locales:, config: {}, raw_config: nil)
    Dir.mktmpdir("locallingo") do |root|
      locales_dir = File.join(root, "config", "locales")
      FileUtils.mkdir_p(locales_dir)

      locales.each do |locale, namespaces|
        namespaces.each do |namespace, tree|
          File.write(
            File.join(locales_dir, "#{namespace}.#{locale}.yml"),
            { locale => { namespace => tree } }.to_yaml
          )
        end
      end

      write_config(root, config, raw_config)
      yield root
    end
  end

  def write_config(root, config, raw_config)
    if raw_config
      File.write(File.join(root, ".locallingo.yml"), raw_config)
    else
      defaults = { "source_locale" => "en", "target_locales" => %w[de] }.merge(config)
      File.write(File.join(root, ".locallingo.yml"), { "defaults" => defaults }.to_yaml)
    end
  end

  # A config resolved against a tmp app.
  def config_for(root, package: nil)
    Locallingo::Configuration.load(root_path: root, package:)
  end

  # Seed a `.i18n-state/<namespace>.<locale>.json` file with raw entries.
  def write_state(root, filename, entries)
    dir = File.join(root, ".i18n-state")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, filename), "#{JSON.pretty_generate(entries)}\n")
  end

  def read_state(root, filename)
    JSON.parse(File.read(File.join(root, ".i18n-state", filename)))
  end
end
