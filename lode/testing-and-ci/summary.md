# Testing, CI and release

## 1. The suite

RSpec with SimpleCov. 11 spec files, 101 examples (`grep -cE '^\s*it[ (]'`
across `spec/**/*_spec.rb`). `.rspec` is `--require spec_helper --format
documentation --color`.

| Spec file | Lines | Examples | Subject |
|---|---|---|---|
| `spec/locallingo/manager_spec.rb` | 456 | 23 | status, validate, translate, accept-edits, sync |
| `spec/locallingo/cli_spec.rb` | 186 | 12 | argument parsing and dispatch, in a tmp app |
| `spec/locallingo/providers/ruby_llm_spec.rb` | 125 | 12 | credential resolution and `chat` |
| `spec/locallingo/configuration_spec.rb` | 105 | 8 | the three-way merge, packages, ERB |
| `spec/locallingo/quality_checker_spec.rb` | 102 | 9 | static checks, `fix!` |
| `spec/rubocop/cop/locallingo/relative_i18n_key_spec.rb` | 78 | 7 | the cop + autocorrect |
| `spec/locallingo/settings_spec.rb` | 72 | 11 | String and callable keys |
| `spec/locallingo/state_store_spec.rb` | 67 | 5 | save/no-churn/trailing newline/pruning |
| `spec/locallingo/key_flattener_spec.rb` | 39 | 5 | flatten / set_nested_value |
| `spec/locallingo/json_extraction_spec.rb` | 36 | 6 | fenced, prose-wrapped, brace-in-string |
| `spec/rubocop/cop/locallingo/strftime_in_view_spec.rb` | 31 | 3 | the cop + the `value:` exemption |

There is **no spec file for `Reporter` and none for the four validators** — both
are exercised only through `manager_spec.rb` and `cli_spec.rb`. A change to a
violation's shape or to a printed line is caught, if at all, by those two.

## 2. Fixtures and stubs

Two support files, both auto-required by `spec_helper.rb`'s
`Dir[File.join(__dir__, "support", "**", "*.rb")]`:

- `spec/support/locale_fixtures.rb` — `with_app(locales:, config:, raw_config:)`
  builds a throwaway app in `Dir.mktmpdir` with `config/locales/<ns>.<loc>.yml`
  files and a `.locallingo.yml`, and yields the root. Plus `config_for`,
  `write_state(root, "g.de.json", entries)` and `read_state`. Included globally
  via `config.include LocaleFixtures`.
- `spec/support/ruby_llm_stub.rb` — `stub_llm_chat { |payload:, model:,
  instructions:| … }` and `stub_llm_missing_credentials`. Both use
  `allow_any_instance_of(Locallingo::Providers::RubyLLM)`, which is why
  `.rubocop.yml` excludes `spec/support/**/*` from `RSpec/AnyInstance`. The rule
  the stub enforces: **specs never make a network call**.

`spec_helper.rb` also sets `config.order = :random` with `Kernel.srand
config.seed`, `disable_monkey_patching!`, and an `after` hook calling
`Locallingo.reset_settings!` so a configured key cannot leak between examples.

SimpleCov is started with `add_filter "/spec/"` and **no `minimum_coverage`** —
nothing in the repo enforces a coverage floor, despite
`.claude/rules/testing.md` naming 80% / 100% targets.

## 3. Running it

`bundle exec rake` is `spec` then `rubocop` (`task default: %i[spec rubocop]`),
and it is exactly what CI runs. The RuboCop rake task is scoped to
`exe lib spec Rakefile Gemfile locallingo.gemspec` — the `docs/` app has its own
`.rubocop.yml` and its own bundle and is not covered.

`Gemfile.lock` is gitignored at the repo root, so every `bundle install`
re-resolves; `docs/bun.lock` is the only tracked lockfile in the repository.

## 4. CI

`.github/workflows/ci.yml` — one job, `rake`, on `push` to `main` and on every
`pull_request`, Ruby `3.2`, `3.3`, `3.4`, `fail-fast: false`, with a
`concurrency` group that cancels superseded runs on the same ref. Each cell is
`actions/checkout@v4` → `ruby/setup-ruby@v1` with `bundler-cache: true` →
`bundle exec rake`. Nothing else runs on a PR: **the `docs/` app has no PR CI**,
since `deploy-docs.yml` fires only on a published release or a manual dispatch.

A failure in exactly one Ruby cell is a version-specific bug, not a flake: the
gem's floor is Ruby 3.2 (`required_ruby_version`, `TargetRubyVersion: 3.2`), so
3.3+/3.4-only syntax breaks the 3.2 cell first.

`.github/workflows/release.yml` runs on a published release: `test` (the same
rake matrix) → `build` (verify the tag matches `Locallingo::VERSION`, build with
`--strict`, unpack and assert no `.git*`/`*.gemspec`/`spec`/`test` entries,
generate sha256+sha512) → `publish-rubygems` (OIDC trusted publishing in the
`rubygems` environment, Sigstore-signed, skipped if the version is already on
RubyGems) → `upload-release-assets`.

`.github/workflows/deploy-docs.yml` calls
`zoolutions/docs-kit/.github/workflows/deploy.yml@main` with
`image: zoolutions/locallingo`, `service: locallingo`.

## 5. Release

`rake release[X.Y.Z]` (`Rakefile:33-92`) and nothing else moves
`lib/locallingo/version.rb`. It aborts unless the branch is `main` and the tree
is clean, bumps the version file, runs `bundle install --quiet` and
`gem build --strict` as a pre-flight, commits `chore: bump version to X.Y.Z`,
pushes `main` directly, and creates the GitHub release with
`gh release create vX.Y.Z --generate-notes --target main`, which is what fires
both release workflows. `rake release[pre]` keeps the current version and
`--prerelease`s the release; any version string matching `alpha|beta|rc|pre` is
treated as a prerelease.

Releases therefore land on `main` **without a PR**, which is why an ordinary
feature branch must never touch `version.rb`.

`rake build` builds the gem, unpacks it into `/tmp/locallingo-verify`, prints
the file list and cleans up — the local rehearsal of the release job's contents
check.

## See also

- `../workflow.md` — the commands and the CI facts a workflow skill needs
- `../docs-site/summary.md` — the docs app's own tooling
