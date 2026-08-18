# frozen_string_literal: true

require "json"
require "zlib"
require "fileutils"

module Locallingo
  # Reads and writes the source-hash drift state under `state_dir`.
  #
  # State is split into one JSON file per top-level namespace and locale
  # (`accounts.de.json`, ...) so diffs stay small and reviewable. Each entry
  # records the source hash a key was translated from, so a later source change
  # marks the translation outdated. Optionally a `target_hash` and `manual` flag
  # are tracked so hand-edited target values can be protected from overwrites.
  class StateStore
    attr_reader :state_dir

    def initialize(state_dir)
      @state_dir = state_dir
      FileUtils.mkdir_p(@state_dir)
    end

    # CRC32 hash — fast and compact (8 hex chars).
    def self.hash(text)
      format("%08x", Zlib.crc32(text.to_s))
    end

    def hash(text) = self.class.hash(text)

    # Load the combined state for a locale (merged across its namespace files).
    def load(locale)
      combined = {}
      Dir.glob(File.join(state_dir, "*.#{locale}.json")).each do |file|
        combined.merge!(JSON.parse(File.read(file)))
      end
      combined
    rescue JSON::ParserError => e
      raise Error,
            "Corrupted state file: #{e.message}\n" \
            "This would cause state loss. Fix the JSON manually or restore from git."
    end

    # Save a locale's state, split back into per-namespace files. Files whose
    # content is unchanged are left untouched so unrelated namespaces never
    # churn in diffs. Namespace files that no longer have keys are removed.
    def save(locale, locale_state)
      by_namespace = locale_state.each_with_object({}) do |(key, value), groups|
        namespace = key.split(".").first
        (groups[namespace] ||= {})[key] = value
      end

      by_namespace.each do |namespace, keys|
        state_file = File.join(state_dir, "#{namespace}.#{locale}.json")
        content = "#{JSON.pretty_generate(keys.sort.to_h)}\n"
        next if File.exist?(state_file) && File.read(state_file) == content

        File.write(state_file, content)
      end

      Dir.glob(File.join(state_dir, "*.#{locale}.json")).each do |file|
        namespace = File.basename(file).delete_suffix(".#{locale}.json")
        File.delete(file) unless by_namespace.key?(namespace)
      end
    end
  end
end
