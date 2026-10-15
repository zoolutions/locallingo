# Locallingo

AI-assisted i18n translation, drift detection, and quality linting on top of
[i18n-tasks](https://github.com/glebm/i18n-tasks) — packaged as a gem so the same
toolchain works across every app instead of being copy-pasted (and forking) per
repo.

Locallingo:

- **Translates** missing/changed keys through [RubyLLM](https://github.com/crmne/ruby_llm)
  (OpenAI, Anthropic, Google, … — you pick the provider/model).
- **Detects drift** with per-key source hashes, so only genuinely
  missing/outdated keys are re-translated.
- **Validates** translation completeness for CI (missing, outdated, and optional
  duplicate-value / manual-edit checks).
- **Lints quality** — static rules, terminology lists, optional British-spelling
  drift, plus an optional AI review.
- Ships **RuboCop cops** that enforce fully-qualified i18n keys and locale-aware
  date formatting.

Everything app-specific lives in `.locallingo.yml` — target locales, provider and
model, prompt context/glossary, per-language style guides, which validators and
quality rules run, and post-translate hooks — with a default block plus optional
per-package overrides.

## Installation

```ruby
# Gemfile
group :development do
  gem "locallingo"
end
```

Provider credentials come from ENV (e.g. `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`)
or from Ruby, for apps whose keys live elsewhere (Rails credentials, an app
config object, a vault):

```ruby
Locallingo.configure do |config|
  config.anthropic_api_key = "sk-ant-..."            # a String…
  config.openai_api_key = -> { AppConf.openai_key }  # …or a lazy callable
end
```

Put that in a `.locallingo.rb` file next to `.locallingo.yml` and the `lingo`
CLI loads it on start — no Rails boot required. A key set via
`Locallingo.configure` wins over one set through `RubyLLM.configure`, which
wins over ENV. Locallingo never stores keys itself. `configure` publishes the
settings frozen: change them by calling it again, never by writing to
`Locallingo.settings`. Nothing else needs calling at boot. With String keys
the settings are Ractor-shareable; a callable key is kept as it is (resolved on
every use, so it may close over a logger or a vault client), which keeps the
settings readable on the main Ractor only.

## Configuration

Create `.locallingo.yml` at your app root:

```yaml
defaults:
  source_locale: en
  target_locales: [de, sv]

  provider: openai            # any RubyLLM provider
  translate:
    model: gpt-5-mini
  quality:
    model: gpt-4o-mini
    terminology: business     # "business" | "banking" | path/to/terms.yml
    british_spellings: false

  context: "Cosmos, a business application"
  glossary:
    entity: "business/company account holder"
    member: "user belonging to an entity"
  language_guides:
    de: config/locales/.guides/de.md   # inline text or `file:` path

  validators:
    missing: true
    outdated: true
    duplicate_values: true    # flags non-AR keys duplicating an AR attribute value
    manual_edits: false       # protects hand-edited target values

  strict:
    strict:     [missing, outdated]
    strict_all: [missing, outdated, duplicate_value]

  after_translate:
    - "bundle exec i18n-tasks normalize -p"

# Optional per-location overrides (each inherits `defaults`):
packages: []
#  - path: engines/billing
#    context: "the billing engine"
#    target_locales: [de]
```

With no `packages:`, the whole app uses `defaults` — the common case.

## CLI

```bash
lingo status                       # translation status per locale
lingo translate --locale de        # translate missing/changed keys
lingo translate --force            # re-translate everything
lingo translate --force-key a.b.c  # re-translate one key (skips manual; add --include-manual)
lingo validate --strict            # CI gate (exit 1 on strict-tier issues)
lingo validate --strict-all        # stricter CI gate
lingo quality --ai                 # quality linting (+ optional AI pass)
lingo quality --ai --prefix yoga.  # lint one namespace
lingo fix-quality --locale en      # auto-fix fixable issues
lingo accept-edits --locale de     # protect hand-edited translations (drifted keys only)
lingo accept-edits --key a.b.c     # protect a specific key
lingo accept-edits --all           # protect everything (initial adoption)
lingo sync                         # refresh drift state (preserves manual flags)
lingo hash                         # source-translation fingerprint
```

Add `--package engines/billing` to any command to scope it to a package.

The legacy flag forms (`lingo --translate`, `lingo --validate`, …) still work and
print a one-line deprecation notice, so you can migrate CI and docs incrementally.

## RuboCop cops

```yaml
# .rubocop.yml
require:
  - locallingo/rubocop
inherit_gem:
  locallingo: config/default.yml
```

- **`Locallingo/RelativeI18nKey`** — flags relative `t(".key")` lookups and
  autocorrects them to fully-qualified keys derived from the file path and
  enclosing method. Configure `ScopedDirectories` for your layout.
- **`Locallingo/StrftimeInView`** — flags `.strftime(...)` in views; use
  `I18n.l(value, format: :name)` instead. `value:`-pair inputs (HTML datetime)
  are exempt.

Locallingo recommends disabling Rails' `Rails/I18nLazyLookup` and
`Rails/I18nLocaleTexts`, which fight the fully-qualified-key convention.

## Programmatic use

```ruby
config = Locallingo.configuration(root_path: Dir.pwd)
Locallingo::Manager.new(config:).validate           # => [violations]
Locallingo::QualityChecker.new(config:).check(locale: "en")
```

`Locallingo::Configuration.parse(yaml, root_path:, package:)` resolves the same
config from YAML text (ERB included) instead of reading `.locallingo.yml`. A
configuration loaded from the file reads it when it is built, never cached.

### Translating text that is not in locale files

`Locallingo::Translator` runs the same prompt (rules, glossary, language guide),
provider, model and batching over a plain `{ key => text }` hash:

```ruby
require "ruby_llm" # for RubyLLM.context (Bundler.require already loads it in Rails)

translator = Locallingo::Translator.new(
  config: Locallingo.configuration(root_path: Dir.pwd),
  context: RubyLLM.context { |c| c.anthropic_api_key = tenant_key }, # optional, per-tenant key
  pause: 0                                                           # no sleep between batches
)

result = translator.translate(
  { "title" => "Hello", "intro" => "Some **markdown**." },
  from: "en", to: "de",
  style: :prose,                                 # :ui (default) or :prose (keeps Markdown, no brevity rule)
  instructions: "Write in a warm, plain voice."  # appended after the language guide
)
result.translations # => { "title" => "Hallo", "intro" => "Etwas **Markdown**." }
result.failed       # => keys that failed after retries
```

- Every call runs on a `RubyLLM::Context`: the `context:` given, else one
  built for that call from the resolved key. The global `RubyLLM.config` is
  never written, so tenants can translate concurrently.
- `MissingCredentialsError` is raised before any call when no key is found.
- `translate.max_batch_chars` (or `max_batch_chars:`) limits the source
  characters per batch (a single longer value is sent alone, not split); `translate.pause` (or `pause:`) is the sleep after each
  batch. Retries of failed or omitted keys keep their own backoff.
- `Locallingo::Prompt.translation(config:, from:, to:, style:, instructions:)`
  returns the prompt itself.

`Locallingo::Drift` is the missing / outdated / hand-edited rule over the state
entry shape (`source_hash`, `target_hash`, `manual`), for strings or nested
values:

```ruby
drift = Locallingo::Drift.new  # hasher: any callable(String) -> String
drift.status(source:, target:, entry:)  # => :missing | :outdated | :current
drift.due?(source:, target:, entry:, force: false, include_manual: false)
drift.hand_edited?(target:, entry:)
drift.record(source:, target:, manual: false) # => a new entry
```

### Translating records

`require "locallingo/active_record"` (ActiveRecord >= 7.1; nothing loads
ActiveRecord otherwise) adds a concern for a JSON(B) column keyed by locale
plus a JSON(B) state column:

```ruby
class Article < ApplicationRecord
  include Locallingo::Translatable

  translates_content :body,                  # { "en" => { … }, "de" => { … } }
    state: :translation_state,               # { "de" => { "source_hash", "target_hash", "manual" } }
    source_locale: -> { "en" },              # String/Symbol, or a callable run on the record
    target_locales: -> { %w[de sv] },
    translatable: ->(path, value) { true }   # optional filter on flattened String leaves
end

article.translation_status(:de)   # => :missing | :outdated | :current
article.translation_manual?(:de)
article.translation_due?(:de, force: false)
article.record_translation(:de, manual: false)

Locallingo::RecordTranslator.new(translator:)
  .call(Article.where(id: ids), to: "de", style: :prose)
# => { translated: 3, failed: { article_id => [paths] }, skipped: [ids] }
```

- Saving a record runs `mark_hand_edits`: a target locale a person changed is
  flagged `manual` and never machine-overwritten (`include_manual: true`
  overrides, keeping the flag). That includes a target locale saved for the
  first time, e.g. a source copy used as a placeholder at `create!`: leave
  untranslated locales out of the column instead. A cleared locale is not
  flagged and is due again, unless it was already `manual`: the flag stays, so
  retranslating it needs `include_manual: true`.
- `RecordTranslator` sends one batched translation per source locale across all
  due records, then writes each record under `record.with_lock`. A record whose
  source changed, or whose target became manual, while the model answered is
  skipped (`skipped:`) and left for the next run, as is a due record with no
  translatable text.
- Nested values keep their shape; leaves the `translatable:` filter rejects are
  copied from the source. A record with any segment that failed after retries
  is not written at all: its paths are reported in `failed:`, and it stays due
  for the next run (your fallback to the source locale applies meanwhile).
- Writes use `update_columns`; pass `write: ->(record, attributes) { … }` to
  bump a lock version or run validations.
- `translates_content` freezes the declaration as it is made, at boot: the
  column and state names, a String or Array locale option (as a frozen copy)
  and the drift. Callables are kept as they are, so they may close over app
  state; like the model itself, a declaration is read on the main Ractor.

## License

MIT © Mikael Henriksson
