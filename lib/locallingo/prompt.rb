# frozen_string_literal: true

module Locallingo
  # Builds the translation system prompt: idiomatic-translation and formatting
  # rules, the configured glossary and per-language guide, plus optional caller
  # instructions.
  #
  # Styles:
  # - `:ui`    — short interface strings (the CLI's prompt, pinned by a spec)
  # - `:prose` — long-form content: Markdown structure is kept and there is no
  #   brevity rule
  module Prompt
    STYLES = %i[ui prose].freeze

    BREVITY_RULE = "- Keep translations concise - UI space is limited\n"

    MARKDOWN_RULES = <<~RULES
      - Keep the Markdown structure: headings, lists, emphasis, links and line breaks stay where they are
      - Translate link text, never the link target (URL)
      - Never merge or split values: every key gets exactly one translated value
    RULES

    module_function

    def translation(config:, from:, to:, style: :ui, instructions: nil, placeholders: [])
      raise Error, "Unknown prompt style #{style.inspect} (expected one of #{STYLES.join(", ")})" unless
        STYLES.include?(style.to_s.to_sym)

      language = config.language_name(to)
      <<~PROMPT
        Translate the following texts from #{config.language_name(from)} into natural, idiomatic #{language}.
        This is for #{config.context}.

        ## Idiomatic Translation
        - Translate the meaning, not word for word: write what a native #{language} speaker would actually say in this situation
        - Use the phrasing, word order and UI conventions that are standard in #{language} software, even when they differ from the source
        - Replace source-language idioms and set phrases with their natural #{language} equivalent instead of translating them literally
        - Avoid calques and anglicisms when an established #{language} expression exists
        - Never add, drop or change information to make a sentence sound natural
        - Terminology and any language guide below take precedence over these style rules

        ## General Rules
        - Preserve placeholders like #{config.placeholder_style} exactly as they appear
        #{placeholders_rule(placeholders)}- Preserve HTML tags if present
        #{style.to_sym == :prose ? MARKDOWN_RULES : BREVITY_RULE}- Escape every double quote (") inside a translated value as \\" so the reply stays valid JSON
        - Keep typographic quotes (“ ” „ ‚ « ») exactly as they appear in the source
        #{glossary_section(config)}#{language_guide_section(config, to)}#{instructions_section(instructions)}
        Return ONLY a raw JSON object mapping each input key to its translation,
        with no surrounding prose and no markdown code fences:
        {"key1": "translated1", "key2": "translated2"}
      PROMPT
    end

    def placeholders_rule(patterns)
      patterns = Array(patterns)
      return "" if patterns.empty?

      sources = patterns.map { |pattern| "`#{pattern.source}`" }.join(", ")
      "- Preserve every token matching these patterns exactly as it appears, with the same count: #{sources}\n"
    end

    def glossary_section(config)
      return "" if config.glossary.empty?

      lines = config.glossary.map { |term, meaning| "        - \"#{term}\" = #{meaning}" }
      "\n## Terminology\n#{lines.join("\n")}\n"
    end

    def language_guide_section(config, locale)
      guide = config.language_guide(locale)
      guide.empty? ? "" : "\n#{guide}\n"
    end

    def instructions_section(instructions)
      text = instructions.to_s.strip
      text.empty? ? "" : "\n## Additional Instructions\n#{text}\n"
    end

    private_class_method :placeholders_rule, :glossary_section, :language_guide_section, :instructions_section
  end
end
