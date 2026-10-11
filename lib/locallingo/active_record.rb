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
      translation_target_locales.each do |locale|
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

    # The source's translatable String leaves, flattened (`steps[1].text`).
    def translation_segments
      KeyFlattener.flatten(translation_source || {}).select do |path, value|
        value.is_a?(String) && !value.strip.empty? && locallingo_translatable.translatable.call(path, value)
      end
    end

    # The target for translated +segments+ (`path => text`), in the source's
    # nested shape: untranslatable leaves are copied from the source, segments
    # without a translation are left out.
    def build_translation_target(segments)
      translatable = translation_segments
      KeyFlattener.flatten(translation_source || {}).each_with_object({}) do |(path, value), target|
        next KeyFlattener.set_nested_value(target, path, value) unless translatable.key?(path)

        KeyFlattener.set_nested_value(target, path, segments[path]) if segments.key?(path)
      end
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
