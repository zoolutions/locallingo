# frozen_string_literal: true

require "json"
require_relative "state_store"

module Locallingo
  # Missing / outdated / hand-edited decisions over one value and its state
  # entry — the rule locale files and database records share.
  #
  # An entry is the shape StateStore writes:
  #   { "source_hash" => …, "target_hash" => …, "manual" => true }
  #
  # Values may be a String or a nested Hash/Array of strings. A String hashes
  # raw (exactly like StateStore, so existing state files stay valid); nested
  # values hash over a canonical JSON form with sorted keys, so a record can
  # track one entry per field or one per whole value.
  class Drift
    def initialize(hasher: StateStore.method(:hash))
      @hasher = hasher
    end

    def digest(value)
      case value
      when Hash, Array then @hasher.call(JSON.generate(canonical(value)))
      else @hasher.call(value.to_s)
      end
    end

    # A new entry for a target translated (or written by hand) from +source+.
    def record(source:, target:, manual: false)
      entry = { "source_hash" => digest(source), "target_hash" => digest(target) }
      entry["manual"] = true if manual
      entry
    end

    # :missing (blank target), :outdated (source changed since the entry was
    # recorded) or :current. The manual flag is not considered here; #due?
    # applies it.
    def status(source:, target:, entry:)
      return :missing if blank?(target)
      return :outdated if outdated?(source:, entry:)

      :current
    end

    # The source changed since +entry+ recorded it. An untracked value (no
    # entry or no source_hash) is not outdated.
    def outdated?(source:, entry:)
      stored = entry.is_a?(Hash) ? entry["source_hash"] : nil
      !stored.nil? && stored != digest(source)
    end

    # A person wrote the target: it must not be machine-overwritten.
    def manual?(entry) = entry.is_a?(Hash) && entry["manual"] ? true : false

    # The target changed since it was recorded and is not yet flagged manual.
    def hand_edited?(target:, entry:)
      return false unless entry.is_a?(Hash) && !manual?(entry)

      stored = entry["target_hash"]
      !stored.nil? && stored != digest(target)
    end

    # Whether the target should be (re)translated: missing or outdated, every
    # value with +force+, and never a manual one unless +include_manual+.
    def due?(source:, target:, entry:, force: false, include_manual: false)
      return false if blank?(source)
      return false if manual?(entry) && !include_manual
      return true if force

      status(source:, target:, entry:) != :current
    end

    # Empty, whitespace-only, or a Hash/Array with only blank leaves.
    def blank?(value)
      case value
      when Hash then value.values.all? { |item| blank?(item) }
      when Array then value.all? { |item| blank?(item) }
      else value.to_s.strip.empty?
      end
    end

    private

    def canonical(value)
      case value
      when Hash then value.map { |key, item| [key.to_s, canonical(item)] }.sort_by(&:first).to_h
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
  end
end
