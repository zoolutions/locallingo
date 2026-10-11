# frozen_string_literal: true

require_relative "../drift"

module Locallingo
  module Validators
    # Reports target keys whose recorded source hash no longer matches the
    # current source value — i.e. the English text changed after translation.
    class Outdated
      def initialize(cli_name: "lingo", drift: Drift.new)
        @cli_name = cli_name
        @drift = drift
      end

      # +source+ is the flat source hash; +locale_state+ is the target locale's
      # loaded state (key => { "source_hash" => ... }).
      def call(source:, locale_state:, locale:)
        outdated_keys(source, locale_state).map do |key|
          {
            type: :outdated,
            locale:,
            key:,
            suggestion: suggestion_for(key, locale, locale_state)
          }
        end
      end

      # Keys whose stored source_hash differs from the current source hash.
      def outdated_keys(source, locale_state)
        source.filter_map do |key, value|
          key if @drift.outdated?(source: value, entry: locale_state[key])
        end
      end

      private

      # Manual keys must not be pushed toward machine retranslation — the value
      # is hand-curated, so the human updates it and re-accepts.
      def suggestion_for(key, locale, locale_state)
        if @drift.manual?(locale_state[key])
          "Source changed for a manually-curated key. Update the #{locale} value by hand, " \
            "then run: #{@cli_name} accept-edits --locale #{locale} --key #{key}"
        else
          "Source changed. Run: #{@cli_name} translate --locale #{locale} --force-key #{key}"
        end
      end
    end
  end
end
