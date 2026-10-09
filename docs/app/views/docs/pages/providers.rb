# frozen_string_literal: true

# Choosing an LLM provider and models via RubyLLM.
class Views::Docs::Pages::Providers < DocsUI::Page
  title "Providers & models"
  eyebrow "Configuration"

  def lead = "locallingo translates through RubyLLM, so any provider it supports works — chosen by config."

  def content
    rubyllm
    choosing
    credentials
    models
  end

  private

  def rubyllm
    DocsUI::Section("Provider-agnostic via RubyLLM") do
      md <<~'MD'
        Every translation and quality-review call goes through
        [RubyLLM](https://github.com/crmne/ruby_llm), so locallingo isn't tied to
        one vendor. You pick the provider and models in `.locallingo.yml`; the
        rest of the toolchain is identical regardless of which you choose.
      MD
    end
  end

  def choosing
    DocsUI::Section("Choosing a provider") do
      md <<~'MD'
        Set `provider` to a RubyLLM provider symbol, and the per-task models under
        `translate` and `quality`.
      MD
      DocsUI::Code(<<~'YAML', filename: ".locallingo.yml")
        defaults:
          provider: openai            # or anthropic, gemini, ...
          translate:
            model: gpt-5-mini
          quality:
            model: gpt-4o-mini
      YAML
      DocsUI::Code(<<~'YAML', filename: "anthropic example")
        defaults:
          provider: anthropic
          translate:
            model: claude-haiku-4-5
          quality:
            model: claude-sonnet-4-6
      YAML
    end
  end

  def credentials
    DocsUI::Section("Credentials") do
      md <<~'MD'
        locallingo looks for the configured provider's API key in three places,
        in order — the first non-blank key wins:

        1. **`Locallingo.configure`** — a key set on the gem itself.
        2. **`RubyLLM.configure`** — a key the host app set on RubyLLM directly
           (a Rails initializer, typically).
        3. **ENV** — `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
           and so on.

        A plain ENV var is all most setups need. When your key lives somewhere
        else — Rails credentials, an app config object, a vault — configure the
        gem from Ruby. Values can be Strings or callables; callables are
        resolved fresh on every LLM call, never cached:
      MD
      DocsUI::Code(<<~'RUBY', filename: "Ruby")
        Locallingo.configure do |config|
          config.anthropic_api_key = Rails.application.credentials.anthropic_api_key
          config.openai_api_key = -> { AppConf.openai_api_key }  # resolved lazily
        end
      RUBY
      md <<~'MD'
        ### Standalone CLI runs

        `lingo` doesn't boot Rails, so an initializer never runs for it. Put the
        configure call in a `.locallingo.rb` file next to `.locallingo.yml` —
        the CLI loads it before dispatch:
      MD
      DocsUI::Code(<<~'RUBY', filename: ".locallingo.rb")
        require_relative "config/app_conf"

        Locallingo.configure do |config|
          config.anthropic_api_key = -> { AppConf.anthropic_api_key }
        end
      RUBY
      md <<~'MD'
        locallingo fails fast with a clear message when no source yields a key,
        before making any network call.
      MD
      DocsUI::Callout(:note) do
        plain "Only "
        code { "translate" }
        plain " and the optional "
        code { "quality --ai" }
        plain " pass call the provider. Everything else runs offline."
      end
    end
  end

  def models
    DocsUI::Section("Two models, two jobs") do
      md <<~'MD'
        - `translate.model` does the bulk translation work — favour a fast,
          inexpensive model, since it runs over every missing/changed key in
          batches (`translate.batch_size`, default 20). If a reply is not valid
          JSON, the batch is split in half and retried, down to single keys, so one
          bad value fails only its own key.
        - `quality.model` powers the optional AI review of existing translations —
          a stronger model pays off here because it runs on a sample, not the whole
          corpus.
      MD
    end
  end
end
