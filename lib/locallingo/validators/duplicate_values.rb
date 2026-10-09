# frozen_string_literal: true

module Locallingo
  module Validators
    # Detects source-locale keys whose value matches an
    # `activerecord.attributes.*` value. The AR key wins; the non-AR key is the
    # "duplicate" and should reuse the AR key instead.
    #
    # Operates on the flat source hash only, to avoid false positives from
    # grammatical-form differences in non-English locales.
    class DuplicateValues
      AR_ATTRIBUTES_PREFIX = "activerecord.attributes."
      AR_PREFIX = "activerecord."

      # +source+ is the flat source-locale hash; +locale+ is the configured source
      # locale. Returns :duplicate_value violations naming both keys.
      def call(source:, locale:)
        ar_keys_by_value = source
                           .select { |key, _| key.start_with?(AR_ATTRIBUTES_PREFIX) }
                           .group_by { |_key, value| value }
                           .transform_values { |pairs| pairs.map(&:first) }

        source.filter_map do |key, value|
          # Skip ALL activerecord.* keys (models, attributes, etc.). Rails
          # reserves this namespace for AR-generated translations, and model
          # names colliding with attribute labels is intentional, not a dup.
          next if key.start_with?(AR_PREFIX)
          next unless ar_keys_by_value.key?(value)

          ar_dupes = ar_keys_by_value[value]
          {
            type: :duplicate_value,
            locale:,
            key:,
            suggestion: "Value '#{value}' duplicates #{ar_dupes.join(", ")}. " \
                        "Use #{ar_dupes.first} instead."
          }
        end
      end
    end
  end
end
