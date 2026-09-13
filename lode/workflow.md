# Workflow profile

Everything the shared workflow skills (`/lode:lfg`, `/lode:review-pr`,
`/lode:finish-prs`, `/lode:debug-flaky`, `/lode:tdd`, `/lode:plan`) need to know
about this repository that is not already in `../CLAUDE.md`, `../.claude/rules/`
or the rest of `lode/`.

## Commands

| Purpose | Command | Notes |
|---|---|---|
| fast loop (one file) | `bundle exec rspec <spec file>` | no network, no services; `Dir.mktmpdir` per example |
| full suite | `bundle exec rake` | `spec` then `rubocop` — exactly what CI runs. No network, no services. Safe to run in two worktrees at once: every fixture app is a fresh tmpdir and nothing binds a port or a database |
| lint | `bundle exec rake rubocop` | scoped to `exe lib spec Rakefile Gemfile locallingo.gemspec`; `bundle exec rubocop -A <file>` to autocorrect |
| one CI cell locally | n/a — CI runs the same `bundle exec rake`; switch Ruby with your version manager (3.2, 3.3, 3.4) | |
| docs build / check | `cd docs && bin/rubocop`, `cd docs && bin/ci` (rubocop + bundler-audit + importmap audit + brakeman; there is no test step), `cd docs && bun run build:css` | separate bundle; never run the root `bundle exec rubocop` against `docs/` |
| run the app | `ruby -Ilib exe/lingo <command>` from inside an app directory, or `cd docs && bin/dev` for the docs site | |

## Branches and PRs

- Default branch: `main`
- Work branches: `feature/*`, `fix/*`, `refactor/*`, `ci/*`, `chore/*`, rooted
  off fresh `origin/main`
- **Before switching away from the current branch, stop for work that would be
  left behind.** `git status --porcelain` non-empty → stop and ask; never stash
  silently. If the current branch is not `main`, check for committed-but-unpushed
  commits: verify an upstream exists first (`git rev-parse --verify --quiet
  @{upstream}`) and compare `@{upstream}..`, otherwise the branch was never
  pushed and every commit on it is unpushed, so compare `main..`. Either listing
  commits → stop and name the branch that would be left behind.
- Commits: conventional (`feat:`, `fix:`, `refactor:`, `perf:`, `docs:`,
  `test:`, `chore:`, `ci:`); the body says why, not what
- **Never touch `lib/locallingo/version.rb` in a PR** — `rake release[X.Y.Z]`
  owns it and pushes straight to `main`
- PR body sections, in order: Summary, Test plan, Deviations & judgment calls,
  Gate. Write the body to a file and pass `--body-file`; a heredoc with code
  fences gets mangled
- Merge policy: squash on `main` after green and approval; never rebase a
  published branch — merge `main` forward into it
- Attribution: never add `Co-Authored-By: Claude`, "Generated with Claude Code"
  or any similar AI attribution to a commit, PR body or issue comment

## Layers

| Layer | Files | Edit rule |
|---|---|---|
| CLI | `exe/lingo`, `lib/locallingo/cli.rb`, `lib/locallingo/reporter.rb` | owned here; every printed string is user-facing contract |
| Engine | `lib/locallingo/manager.rb`, `lib/locallingo/key_flattener.rb` | owned here; `manager.rb` is 424 lines against an 800 cap — new behaviour goes in a collaborator |
| State | `lib/locallingo/state_store.rb`, `lib/locallingo/validators/**` | owned here; the protection invariants live here |
| Quality | `lib/locallingo/quality_checker.rb`, `lib/locallingo/quality/**` | owned here |
| Config | `lib/locallingo/configuration.rb`, `lib/locallingo/settings.rb`, `config/locallingo.default.yml` | owned here; a new key needs a shipped default *and* a typed reader |
| Provider | `lib/locallingo/providers/ruby_llm.rb`, `lib/locallingo/json_extraction.rb` | owned here; the only SDK boundary |
| Cops | `lib/rubocop/cop/locallingo/**`, `lib/locallingo/rubocop.rb`, `config/default.yml` | owned here; runs in host apps, never in `lingo` |
| Version | `lib/locallingo/version.rb` | release-owned — never edited in a PR |
| Docs site | `docs/**` | owned here, separate bundle; a page needs its `Doc` registry line |
| Generated | `docs/app/assets/stylesheets/tailwind.sources.css`, `docs/app/assets/builds/*` | generated — edit `bin/build-css`, never the output |

## Shapes

Check a change against these before calling it done:

- A key with **no state entry** (never translated) — not outdated, only missing
- A key whose state entry is not a Hash, or is a Hash with no `target_hash`
- A key already carrying `manual: true`
- A **non-String leaf** in a locale file (integer, boolean, nil) — dropped by the
  loader, so it never reaches translate, validate or quality
- An **array-valued** key (`items[0]`, `items[0].name`) through flatten → set
- A locale file at `config/locales/<locale>.yml` (no namespace in the filename)
  as well as `config/locales/<ns>.<locale>.yml`, and nested subdirectories
- A source locale that is not `en` (`DuplicateValues` hard-codes `"en"`)
- A locale with no builtin language name (falls back to the bare code)
- `--package <path>` scoping, which moves `locales_dir`, `state_dir` and the log
- A config file that is absent entirely, and one with `packages:` but no match
- `--dry-run` on every writer
- An LLM reply that is fenced, prose-wrapped, brace-carrying, an array, or empty
- Ruby 3.2 (the floor) — no 3.3+/3.4-only syntax

## Constraints

Reviewer suggestions that are wrong here, with the reason.

| Suggestion | Why it is wrong here |
|---|---|
| "Bump the version in this PR" | `rake release[X.Y.Z]` owns `version.rb` and pushes to `main` without a PR |
| "Reset corrupted state and carry on" | state loss is unrecoverable; `StateStore#load` raises on purpose |
| "Recompute `target_hash` during sync" | that silently absorbs hand-edit drift — `||=` is deliberate |
| "Always rewrite the state file for consistency" | byte-identical files are skipped so unrelated namespaces never churn a diff |
| "Drop the legacy `--flag` forms" | they are supported with a deprecation notice; removing them is a breaking change |
| "Add `bundler-audit` / `rubocop` as a runtime dependency" | `rubocop` is a development dependency loaded lazily by `locallingo/rubocop`; `bundler-audit` is not a project dependency at all (see `review/commands-and-docs.md`) |
| "Gitignore `docs/app/assets/stylesheets/tailwind.sources.css`" | rejected upstream in docs-kit; see `review/commands-and-docs.md` |
| "Use 3.3+ syntax" | the gemspec floor and `TargetRubyVersion` are 3.2 |

## Docs

- User-facing docs live in `docs/app/views/docs/pages/`; the page-to-behaviour
  map is `docs-site/summary.md` §2. A page also needs its `page "…"` line in
  `docs/app/models/doc.rb`
- `README.md` carries the same facts in short form — a CLI or config change
  updates it too
- Changelog: `CHANGELOG.md`, Keep a Changelog format, entries under
  `## [Unreleased]` in an `### Added` / `### Changed` / `### Fixed` subsection
- A change to a CLI option updates the `cli` **and** `commands` pages; a new
  config key updates `configuration` **and** `configuration-reference`; a change
  to state semantics updates `drift-state` **and** `commands`
- Files that pin a version and drift after a release: none. The root
  `Gemfile.lock` is gitignored and `docs/Gemfile.lock` is not committed;
  `docs/bun.lock` is the only tracked lockfile

## CI

- Workflows: `ci.yml` (`bundle exec rake` on Ruby 3.2/3.3/3.4, on push to `main`
  and every PR, `fail-fast: false`, concurrency-cancelled per ref);
  `release.yml` (on a published release: test → build+verify → RubyGems trusted
  publishing → release assets); `deploy-docs.yml` (on a published release or
  manual dispatch, via docs-kit's reusable workflow)
- Matrix: Ruby only. A cell differs from local only by Ruby version
- Fetch a failure: `gh pr checks <PR>`, then
  `gh run view <RUN_ID> --job=<JOB_ID> --log-failed`
- What "green" means: all three `rake (Ruby X.Y)` cells. A `rake` job fails on
  whichever of spec or rubocop breaks first — read the log to see which half
- Known not-this-branch failures: none recorded
- Shared or rate-limited services the checks hit: none — the suite is fully
  offline, so PRs can run concurrently
- **The `docs/` app has no PR CI.** A docs change is unverified until someone runs
  `cd docs && bin/ci` locally

## Flake sources

- None observed. The suite makes no network call (the provider is stubbed in
  `spec/support/ruby_llm_stub.rb`), binds no port and uses no database.
- The two structural risks, if a flake ever appears: `config.order = :random`
  plus `Locallingo.settings` being process-global memoised state (the
  `after { Locallingo.reset_settings! }` hook in `spec_helper.rb` is what keeps
  that honest), and `Dir.chdir` inside `cli_spec.rb`'s `run_cli` helper, which is
  not thread-safe if examples are ever parallelised.
- `Manager`'s retry paths call real `sleep` (`BASE_SLEEP_DURATION = 1.0`, doubled
  per round) — a spec that exercises a retry without stubbing `sleep` is slow,
  not flaky.

## Conflicts

| File | Rule |
|---|---|
| `docs/bun.lock` | never hand-merge: take the base's, then `bun install --cwd docs` |
| `CHANGELOG.md` | union under `## [Unreleased]`, keeping both sides' bullets, without duplicating the `### Added`/`### Changed`/`### Fixed` subheads |
| `lib/locallingo/version.rb` | a feature branch never edits it — take the base's, unless the branch's own commits show a deliberate release-prep bump |
| `config/locallingo.default.yml`, `config/default.yml` | usually different keys on each side: keep both, then confirm the result is YAML the gem still loads |
| `docs/app/models/doc.rb` | append-only registry — base order first, then the branch's new `page` lines |
| `spec/support/locale_fixtures.rb` | add a helper rather than reshaping an existing one; both sides' specs call it |
| everything else | source — merge semantically, never blanket `--ours`/`--theirs` |

The root `Gemfile.lock` and `docs/Gemfile.lock` are untracked and cannot
conflict.

## Verification

- The manual check a user of a change would do: build a scratch app
  (`config/locales/<ns>.en.yml` + `.locallingo.yml`), run
  `ruby -Ilib exe/lingo status`, then the command you changed, and read both the
  printed output and the resulting `.i18n-state/*.json`
- Stress iterations for a flake proof: 50 (`bundle exec rspec <file> --seed <n>`
  across seeds, since order is random)
- Where evidence goes: `lode/tmp/` (git-ignored), unless the PR needs an
  auditable trail
