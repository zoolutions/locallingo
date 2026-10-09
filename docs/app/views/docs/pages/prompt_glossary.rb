# frozen_string_literal: true

# Shaping the translation prompt: context, glossary, placeholders, guides.
class Views::Docs::Pages::PromptGlossary < DocsUI::Page
  title "Prompt & glossary"
  eyebrow "Configuration"

  def lead = "Tune what the model knows about your product so translations read right."

  def content
    idiomatic
    context_section
    glossary
    placeholders
    guides
  end

  private

  def idiomatic
    DocsUI::Section("Idiomatic by default") do
      md <<~'MD'
        Every translation prompt asks for natural, idiomatic text in the target
        language — what a native speaker would actually write in your UI — not a
        word-for-word rendering of the source. The model is told to use the target
        language's own phrasing and software conventions, swap idioms for their
        local equivalent, and avoid calques, without adding or dropping
        information. Use `language_guides` below to tighten the style per locale.
      MD
    end
  end

  def context_section
    DocsUI::Section("Context") do
      md <<~'MD'
        `context` names your product and domain in one phrase. It's woven into the
        translation prompt so the model translates for *your* application rather
        than generic text.
      MD
      DocsUI::Code(<<~'YAML', filename: ".locallingo.yml")
        defaults:
          context: "Acme, a business banking application"
      YAML
    end
  end

  def glossary
    DocsUI::Section("Glossary") do
      md <<~'MD'
        `glossary` pins domain terms the model must not paraphrase — the exact
        words that carry meaning in your app. Each entry becomes a line in the
        prompt's terminology section.
      MD
      DocsUI::Code(<<~'YAML', filename: ".locallingo.yml")
        defaults:
          glossary:
            entity: "business/company account holder"
            member: "user belonging to an entity"
      YAML
    end
  end

  def placeholders
    DocsUI::Section("Placeholder style") do
      md <<~'MD'
        `placeholder_style` documents your interpolation syntax so the model
        preserves it verbatim instead of translating inside it. Set it to whatever
        your locales use — Kernel-format `%<name>s` or Ruby-I18n `%{name}`.
      MD
      DocsUI::Code(<<~'YAML', filename: ".locallingo.yml")
        defaults:
          placeholder_style: "%<name>s, %<count>s"
      YAML
    end
  end

  def guides
    DocsUI::Section("Per-language style guides") do
      md <<~'MD'
        `language_guides` appends extra guidance per target locale — formality,
        compound-noun rules, number formatting, quotation marks. A value is inline
        text or a `file:` path (read relative to the config's base path), so long
        guides can live in their own Markdown file.
      MD
      DocsUI::Code(<<~'YAML', filename: ".locallingo.yml")
        defaults:
          language_guides:
            de:
              file: config/locales/.guides/de.md
            sv: "Use formal Swedish; å, ä, ö correctly; 1 234,56 number format."
      YAML
      DocsUI::Code(<<~'GUIDE', filename: "config/locales/.guides/de.md", lexer: :markdown)
        ## German Language Guidelines
        - Use "Sie" (formal), not "du" — this is a business application.
        - Use proper German compound nouns (e.g. "Kontoeinstellungen").
        - Avoid anglicisms where a German equivalent exists.
        - Nouns are always capitalized; use „…" quotation marks.
        - Numbers use German formatting (1.234,56).
      GUIDE
    end
  end
end
