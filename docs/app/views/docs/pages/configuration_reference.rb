# frozen_string_literal: true

# Every .locallingo.yml key, its default, and what it does.
class Views::Docs::Pages::ConfigurationReference < DocsUI::Page
  title "Configuration reference"
  eyebrow "Configuration"

  def lead = "Every key under defaults: (and packages:), with its default value."

  def content
    locations
    provider_models
    prompt
    validators
    strict
    hooks
    packages
  end

  private

  def locations
    DocsUI::Section("Locales & state") do
      md <<~'MD'
        | Key | Default | Description |
        | --- | --- | --- |
        | `source_locale` | `en` | Locale you author in and translate *from* |
        | `target_locales` | `[de, sv]` | Locales to translate *to* |
        | `locales_dir` | `config/locales` | Where the `<namespace>.<locale>.yml` files live |
        | `state_dir` | `.i18n-state` | Where source-hash drift state is tracked |
      MD
    end
  end

  def provider_models
    DocsUI::Section("Provider & models") do
      md <<~'MD'
        | Key | Default | Description |
        | --- | --- | --- |
        | `provider` | `openai` | RubyLLM provider symbol |
        | `translate.model` | `gpt-5-mini` | Model for bulk translation |
        | `translate.batch_size` | `20` | Keys per translation request |
        | `quality.model` | `gpt-4o-mini` | Model for the AI quality pass |
        | `quality.british_spellings` | `false` | Flag en-only American→British drift |
        | `quality.sample_size` | `100` | How many keys `quality --ai` samples per run |
        | `quality.terminology` | `business` | `business`, `banking`, `none`, or a path to a YAML list |
      MD
    end
  end

  def prompt
    DocsUI::Section("Prompt scaffolding") do
      md <<~'MD'
        | Key | Default | Description |
        | --- | --- | --- |
        | `context` | `"a business application"` | One-phrase product/domain description |
        | `placeholder_style` | `"%<name>s, %<count>s"` | Interpolation syntax to preserve |
        | `glossary` | `{}` | Domain terms the model must not paraphrase |
        | `language_guides` | `{}` | Per-locale guidance for the translation and AI quality prompts (inline text or `file:` path) |
      MD
    end
  end

  def validators
    DocsUI::Section("Validators") do
      md <<~'MD'
        | Key | Default | Description |
        | --- | --- | --- |
        | `validators.missing` | `true` | Report keys absent from a target locale |
        | `validators.outdated` | `true` | Report keys whose source changed after translation |
        | `validators.duplicate_values` | `false` | Flag non-AR keys duplicating an `activerecord.attributes.*` value |
        | `validators.manual_edits` | `false` | Flag hand-edited target values so they aren't overwritten |
      MD
    end
  end

  def strict
    DocsUI::Section("Strict tiers") do
      md <<~'MD'
        Each tier lists the violation *types* that make `validate` exit non-zero.

        | Key | Default | Used by |
        | --- | --- | --- |
        | `strict.strict` | `[missing, outdated]` | `validate --strict` |
        | `strict.strict_all` | `[missing, outdated, duplicate_value]` | `validate --strict-all` |
      MD
    end
  end

  def hooks
    DocsUI::Section("Hooks") do
      md <<~'MD'
        | Key | Default | Description |
        | --- | --- | --- |
        | `after_translate` | `["bundle exec i18n-tasks normalize -p"]` | Commands run (in order) after a successful translate |
      MD
      DocsUI::Callout(:note) do
        plain "Add "
        code { "bundle exec rails i18n:export" }
        plain " to "
        code { "after_translate" }
        plain " if you also export locales for JavaScript."
      end
    end
  end

  def packages
    DocsUI::Section("Packages") do
      md <<~'MD'
        | Key | Default | Description |
        | --- | --- | --- |
        | `packages` | `[]` | Per-location overrides; each has a `path` plus any keys to override |

        See [Multiple packages](/docs/packages).
      MD
    end
  end
end
