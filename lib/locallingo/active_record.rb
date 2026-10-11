# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/class/attribute"

require_relative "../locallingo"

module Locallingo
  # Opt-in ActiveRecord concern (`require "locallingo/active_record"`) for the
  # common shape: a JSON(B) column keyed by locale plus a JSON(B) state column
  # holding one Drift entry per target locale. Supports ActiveRecord >= 7.1.
  #
  #   class Article < ApplicationRecord
  #     include Locallingo::Translatable
  #
  #     translates_content :body,                # { "en" => { … }, "de" => { … } }
  #       state: :translation_state,             # { "de" => { "source_hash", "target_hash", "manual" } }
  #       source_locale: -> { "en" },            # String/Symbol, or a callable run on the record
  #       target_locales: -> { %w[de sv] },
  #       translatable: ->(path, value) { true } # optional filter on flattened String leaves
  #   end
  #
  # A `before_save` callback (#mark_hand_edits) flags target locales a person
  # changed as manual, so Locallingo::RecordTranslator never overwrites them.
  module Translatable
    extend ActiveSupport::Concern

    Definition = Data.define(:column, :state, :source_locale, :target_locales, :translatable, :drift)

    included do
      class_attribute :locallingo_translatable, instance_writer: false
    end

    class_methods do
      def translates_content(column, state:, source_locale:, target_locales:, translatable: nil, hasher: nil)
        self.locallingo_translatable = Definition.new(
          column: column.to_s, state: state.to_s, source_locale:, target_locales:,
          translatable: translatable || ->(_path, _value) { true },
          drift: hasher ? Drift.new(hasher:) : Drift.new
        )
        before_save :mark_hand_edits
      end
    end

    def translation_source_locale = resolve_translation_option(locallingo_translatable.source_locale).to_s

    def translation_target_locales
      Array(resolve_translation_option(locallingo_translatable.target_locales)).map(&:to_s)
    end

    def translation_source = translation_content[translation_source_locale]
    def translation_target(locale) = translation_content[locale.to_s]
    def translation_entry(locale) = translation_states[locale.to_s]
    def translation_source_digest = translation_drift.digest(translation_source)

    def translation_status(locale)
      translation_drift.status(source: translation_source, target: translation_target(locale),
                               entry: translation_entry(locale))
    end

    def translation_manual?(locale) = translation_drift.manual?(translation_entry(locale))

    def translation_due?(locale, force: false, include_manual: false)
      translation_drift.due?(source: translation_source, target: translation_target(locale),
                             entry: translation_entry(locale), force:, include_manual:)
    end

    # Records the current source and target of +locale+ as its state entry
    # (assigned, not saved).
    def record_translation(locale, manual: false)
      entry = translation_drift.record(source: translation_source, target: translation_target(locale), manual:)
      self[locallingo_translatable.state] = translation_states.merge(locale.to_s => entry)
    end

    # Flags every target locale a person changed as manual: a recorded target
    # that no longer matches its target_hash, or an untracked locale written in
    # this save. A cleared target is not flagged — it is missing and due again.
    def mark_hand_edits
      (translation_target_locales - [translation_source_locale]).each do |locale|
        target = translation_target(locale)
        next if translation_drift.blank?(target)

        entry = translation_entry(locale)
        next unless translation_drift.hand_edited?(target:, entry:) || (entry.nil? && translation_written?(locale))

        # A recorded source_hash is kept: a hand edit does not make an
        # outdated translation current.
        manual = translation_drift.record(source: translation_source, target:, manual: true)
        manual["source_hash"] = entry["source_hash"] if entry&.key?("source_hash")
        self[locallingo_translatable.state] = translation_states.merge(locale => manual)
      end
    end

    # The source's translatable String leaves, flattened (`steps[1].text`,
    # `table[0][1]`). Unlike KeyFlattener, strings in nested arrays count.
    def translation_segments
      translation_leaves.filter_map do |path, (_, value)|
        next unless value.is_a?(String) && !value.strip.empty?

        [path, value] if locallingo_translatable.translatable.call(path, value)
      end.to_h
    end

    # The target for translated +segments+ (`path => text`): a deep copy of the
    # source with each translated leaf set in place, so every other value and
    # container (numbers, nested lists, empty ones) keeps its place.
    def build_translation_target(segments)
      target = JSON.parse(JSON.generate(translation_source || {}))
      leaves = translation_leaves
      segments.each do |path, text|
        *parents, last = leaves.fetch(path).first
        (parents.empty? ? target : target.dig(*parents))[last] = text
      end
      target
    end

    # Column attributes that write +target+ for +locale+ plus its state entry.
    def translation_attributes(locale, target, manual: false)
      locale = locale.to_s
      entry = translation_drift.record(source: translation_source, target:, manual:)
      {
        locallingo_translatable.column => translation_content.merge(locale => target),
        locallingo_translatable.state => translation_states.merge(locale => entry)
      }
    end

    def translation_drift = locallingo_translatable.drift

    private

    # `path => [parts, value]` for every leaf of the source, where parts are
    # the Hash keys and Array indices leading to it.
    def translation_leaves(value = translation_source || {}, parts = [], leaves = {})
      case value
      when Hash then value.each { |key, item| translation_leaves(item, parts + [key.to_s], leaves) }
      when Array then value.each_with_index { |item, index| translation_leaves(item, parts + [index], leaves) }
      else leaves[translation_path(parts)] = [parts, value]
      end
      leaves
    end

    def translation_path(parts)
      parts.each_with_index.map do |part, index|
        next "[#{part}]" if part.is_a?(Integer)

        index.zero? ? part : ".#{part}"
      end.join
    end

    def translation_content = self[locallingo_translatable.column] || {}
    def translation_states = self[locallingo_translatable.state] || {}

    def translation_written?(locale)
      column = locallingo_translatable.column
      return false unless will_save_change_to_attribute?(column)

      (attribute_in_database(column) || {})[locale] != translation_target(locale)
    end

    def resolve_translation_option(option)
      option.respond_to?(:call) ? instance_exec(&option) : option
    end
  end
end
