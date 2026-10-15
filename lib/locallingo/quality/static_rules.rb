# frozen_string_literal: true

module Locallingo
  module Quality
    # Regex-based, provider-free translation-quality rules. Ported from the
    # original TranslationQualityChecker STATIC_RULES / UNIVERSAL_FIXES.
    module StaticRules
      # Locale-agnostic auto-fixable corrections.
      UNIVERSAL_FIXES = {
        "can not" => "cannot",
        "Can not" => "Cannot"
      }.freeze

      # Every level frozen, so any Ractor can read the rules.
      RULES = {
        terminology: {
          /\bcan not\b/i => "Use 'cannot' (one word)",
          /\blogin\s+(to|regularly|now|here|again|first|using|with)\b/i =>
            "Use 'log in' (verb) not 'login' here",
          /\bclick\s+here\b/i => "Avoid 'click here' - use descriptive link text",
          /\bplease\b.*\bplease\b/i => "Multiple 'please' in same text - remove redundancy"
        }.freeze,
        placeholders: {
          /%\{[^}]*\s[^}]*\}/ => "Placeholder contains spaces - may cause issues",
          /%\{[A-Z]/ => "Placeholder starts with uppercase - convention is lowercase"
        }.freeze,
        clarity: {
          /\betc\.?\b/i => "Avoid 'etc.' - be specific or use 'and more'",
          /\bstuff\b/i => "Vague word 'stuff' - be more specific",
          /\bthings\b/i => "Vague word 'things' - be more specific",
          /\basap\b/i => "Avoid abbreviation 'ASAP' - use 'as soon as possible'",
          /\bfyi\b/i => "Avoid abbreviation 'FYI' - rephrase",
          /\s{2,}/ => "Multiple consecutive spaces"
        }.freeze,
        business: {
          /\bsorry\b/i => "Consider 'We apologize' for formal business tone",
          /\boops\b/i => "Informal - use professional error messaging",
          /\buh\s*oh\b/i => "Informal - use professional error messaging",
          /\bawesome\b/i => "Consider more professional alternatives",
          /\bcool\b(?!\s*down)/i => "Informal - consider 'great' or 'excellent'"
        }.freeze,
        accessibility: {
          /\bsee\s+below\b/i => "Screen reader unfriendly - describe the content",
          /\babove\b/i => "Positional reference - may not work for all users",
          /\bred\b.*\berror\b|\berror\b.*\bred\b/i => "Don't rely on color alone for meaning"
        }.freeze
      }.freeze

      module_function

      # Suggestions from the regex RULES for one key/text pair.
      def check(key, text, locale)
        suggestions = []

        RULES.each do |category, rules|
          rules.each do |pattern, message|
            next unless text.match?(pattern)

            suggestions << {
              key:, text:, locale:, category:,
              issue: message,
              match: text.match(pattern).to_s,
              severity: severity_for_category(category),
              source: :static
            }
          end
        end

        suggestions
      end

      # Auto-fixable universal fixes for one key/text pair.
      def universal_fixes(key, text, locale)
        UNIVERSAL_FIXES.filter_map do |wrong, correct|
          next unless text.include?(wrong)

          {
            key:, text:, locale:,
            category: :grammar,
            issue: "Use '#{correct}' instead of '#{wrong}'",
            match: wrong,
            fix: { from: wrong, to: correct },
            severity: :warning,
            source: :static
          }
        end
      end

      def severity_for_category(category)
        case category
        when :placeholders then :error
        when :terminology, :accessibility then :warning
        else :info # :clarity, :business, :length, etc.
        end
      end
    end
  end
end
