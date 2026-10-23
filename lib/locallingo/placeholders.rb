# frozen_string_literal: true

module Locallingo
  # Token checks for translated text: the tokens a list of patterns matches
  # (`{{ item.name }}`, `%{count}`, …) must survive translation unchanged, in
  # the same count. Order may change, since word order does. Pure functions
  # over their arguments.
  module Placeholders
    module_function

    # Every whole match of every pattern in +text+, pattern by pattern.
    def tokens(text, patterns)
      patterns.flat_map { |pattern| text.to_s.gsub(pattern).to_a }
    end

    # nil when +translated+ holds exactly the tokens of +source+, else
    # `{ "missing" => [...], "extra" => [...] }` (multiset difference on the
    # exact matched text).
    def compare(source, translated, patterns)
      before = tokens(source, patterns).tally
      after = tokens(translated, patterns).tally
      missing = difference(before, after)
      extra = difference(after, before)
      return nil if missing.empty? && extra.empty?

      { "missing" => missing, "extra" => extra }
    end

    def difference(counts, other)
      counts.flat_map { |token, count| [token] * [count - other.fetch(token, 0), 0].max }
    end

    private_class_method :difference
  end
end
