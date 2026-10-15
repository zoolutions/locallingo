# frozen_string_literal: true

require "yaml"

module Locallingo
  module Quality
    # Business/domain terminology checks. A term maps to a suggestion string, or
    # to nil when the term is acceptable (present only so it is documented as
    # reviewed). Selected by `quality.terminology`: a built-in name ("business",
    # "banking", "none") or a path to a custom YAML file.
    class Terminology
      # Generic business terminology (the cosmos-2 default).
      BUSINESS = {
        "wire transfer" => "Consider 'bank transfer' for broader understanding",
        "checking account" => "Use 'current account' for non-US markets",
        "savings account" => nil,
        "routing number" => "Use 'sort code' (UK) or 'branch code' for non-US",
        "zip code" => "Use 'postal code' for international audiences",
        "transaction" => nil,
        "company" => nil,
        "business" => nil,
        "customer" => nil,
        "client" => nil,
        "beneficiary" => nil,
        "payee" => nil,
        "kyc" => nil,
        "kyb" => nil
      }.freeze

      # Banking terminology (the zazu/app default) — a superset of BUSINESS with
      # extra always-acceptable regulatory terms.
      BANKING = BUSINESS.merge(
        "know your customer" => nil,
        "know your business" => nil,
        "aml" => nil,
        "cdd" => nil
      ).freeze

      BUILTINS = { "business" => BUSINESS, "banking" => BANKING, "none" => {}.freeze }.freeze

      attr_reader :terms

      # +setting+ is a built-in name, a path to a YAML file, or nil (=> business).
      def initialize(setting, base_path: Dir.pwd)
        @terms = resolve(setting, base_path)
      end

      # Suggestions for flagged (non-nil) terms found in +text+.
      def check(key, text, locale)
        terms.filter_map do |term, suggestion|
          next unless suggestion
          next unless text.downcase.include?(term.downcase)

          {
            key:, text:, locale:,
            category: :terminology,
            issue: suggestion,
            match: term,
            severity: :info,
            source: :static
          }
        end
      end

      private

      def resolve(setting, base_path)
        return BUSINESS if setting.nil?
        return BUILTINS.fetch(setting) if BUILTINS.key?(setting)

        path = File.expand_path(setting, base_path)
        raise Error, "Unknown terminology #{setting.inspect} (not a builtin or a file)" unless File.exist?(path)

        YAML.safe_load_file(path) || {}
      end
    end
  end
end
