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
wins over ENV. Locallingo never stores keys itself.

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

## License

MIT © Mikael Henriksson
