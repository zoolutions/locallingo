# frozen_string_literal: true

require "json"

module Locallingo
  # Extracts a JSON object from an LLM response.
  #
  # Not every provider has a native "JSON-only" mode (Anthropic, unlike OpenAI's
  # `response_format: json_object`, does not), so a model may wrap its object in
  # a ```json fence or add a sentence of prose around it. This recovers the
  # object from those shapes.
  #
  # The naive `text[/\{.*\}/m]` (greedy) is unsafe: a brace anywhere in the
  # surrounding prose — very likely here, since the translation prompts are all
  # about preserving `%{placeholder}`s the model may echo — extends the captured
  # span past the real object and JSON.parse raises. So we try, in order: the
  # whole string, a fenced block, then a brace-balanced scan from the first `{`
  # that respects string literals and escapes.
  module JsonExtraction
    module_function

    # Returns the parsed Hash, or raises JSON::ParserError if no JSON object can
    # be recovered (or the top-level value is not an object).
    def extract_object(content)
      text = content.to_s.strip

      fenced = fenced_block(text)
      parsed = try_parse(text) ||
               try_parse(fenced) ||
               first_balanced_object(text) ||
               raise_parse_error(text, fenced)

      # Both callers treat the result as a key->value Hash, so reject a
      # top-level array (or any non-object) here with a clear contract error
      # rather than letting `.keys`/`.map` fail confusingly downstream.
      return parsed if parsed.is_a?(Hash)

      raise JSON::ParserError, "Expected a top-level JSON object, got #{parsed.class}"
    end

    # nil on failure so the `||` chain falls through to the next strategy.
    def try_parse(candidate)
      return nil if candidate.nil?

      JSON.parse(candidate)
    rescue JSON::ParserError
      nil
    end

    # Raise the most useful parse error. A complete fence that fails to parse
    # holds the real fault (e.g. an unescaped quote inside a value); parsing the
    # raw text would only report the fence itself at line 1.
    def raise_parse_error(text, fenced)
      JSON.parse(fenced || text)
    rescue JSON::ParserError => e
      raise e unless fenced

      raise JSON::ParserError, "#{e.message} (inside the fenced block)"
    end

    def fenced_block(text)
      text[/```(?:json)?\s*(\{.*?\}|\[.*?\])\s*```/m, 1]
    end

    # Try each `{` in the text as a candidate object start (prose can contain
    # stray braces — e.g. a `%{name}` placeholder echoed before the real JSON),
    # and return the first balanced span that parses as a JSON object.
    def first_balanced_object(text)
      offset = text.index("{")

      while offset
        candidate = balanced_object(text, offset)
        parsed = try_parse(candidate) if candidate
        return parsed unless parsed.nil?

        offset = text.index("{", offset + 1)
      end

      nil
    end

    # Scan from `start` tracking brace depth, ignoring braces inside string
    # literals (honoring backslash escapes), and return the substring up to the
    # matching close brace (or nil if unbalanced).
    def balanced_object(text, start)
      depth = 0
      in_string = false
      escaped = false

      text[start..].each_char.with_index do |char, index|
        if in_string
          if escaped then escaped = false
          elsif char == "\\" then escaped = true
          elsif char == '"' then in_string = false
          end
          next
        end

        case char
        when '"' then in_string = true
        when "{" then depth += 1
        when "}"
          depth -= 1
          return text[start, index + 1] if depth.zero?
        end
      end

      nil
    end
  end
end
