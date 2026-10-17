# Locallingo

Project instructions for every agent: Claude Code (`CLAUDE.md` imports this file), Grok, Cursor,
Copilot, Codex read it directly. The delivery workflow comes from the shared `flow` and `ruby-gem`
plugins (`.claude/settings.json`); the repo-specific facts they act on are under Workflow.

AI-assisted i18n translation, drift detection, and quality linting on top of
i18n-tasks — packaged as a gem (ships the `lingo` CLI).

## Tech Stack

- **Ruby**: >= 3.2 (CI matrix: 3.2, 3.3, 3.4, 4.0; the Ractor canary runs on 4.0 only)
- **Translation**: RubyLLM (OpenAI, Anthropic, Google, … — provider-agnostic)
- **i18n plumbing**: i18n-tasks
- **Testing**: RSpec + SimpleCov
- **Linting**: RuboCop (the gem also ships its own cops)

## Critical Rules

### Never Do
1. **NO version bumps in PRs** — `bin/release` (→ `rake release[x.y.z]`) owns `version.rb`; PRs must not touch it
2. **NO storing or logging API keys** — keys come from ENV, `Locallingo.configure`, or `RubyLLM.configure`; never persist them
3. **NO dropping `manual` flags from state** — sync is non-destructive; hand-edit protection must survive every state rewrite
4. **NO rewriting unchanged state files** — `StateStore#save` skips byte-identical files so diffs stay small; keep it that way
5. **NO state files without a trailing final newline** — writer output must be POSIX-conformant and idempotent

### Always Do
1. **TDD**: Write tests BEFORE implementation
2. **State safety first**: state corruption raises (`Locallingo::Error`) rather than silently losing drift data
3. **Config-driven behavior**: anything app-specific belongs in `.locallingo.yml` (`defaults` + per-`packages` overrides), never hardcoded
4. **Backwards compatibility**: legacy CLI flag forms (`lingo --translate`, …) keep working with a deprecation notice
5. **Coverage**: 80% minimum; 100% for `StateStore`, the Manager sync/accept-edits paths (manual-flag preservation), the validators and Configuration/Settings resolution. Errors raise `Locallingo::Error` with an actionable message

## Commands

```bash
bundle exec rspec          # Run tests
bundle exec rake rubocop   # Lint (scoped to exe/lib/spec/rakelib/Rakefile/Gemfile/gemspec)
bundle exec rake           # Both — this is what CI runs
bundle exec rake build     # Build gem and verify contents
bin/release                # Release (version bump + tag + push via rake release[x.y.z]) — maintainer only
```

Command output is condensed by rtk (PreToolUse hook). `.rtk/filters.toml` covers this repo's
`rake` tasks (`bundle exec rake`, `bundle exec rake rubocop` — the Rakefile wraps rspec/rubocop,
so the hook's built-in rspec/rubocop rewrites don't catch them); every edit to it needs
`rtk trust --yes` + `rtk verify`. Write commands in hook-rewritable shapes: no `for`/subshell
wrappers, no `| head` on rtk-handled commands, `bundle exec rubocop` not `bin/rubocop`.

## Slash Commands

`/flow:*` and `/ruby-gem:*` come from the plugins. Local: `/security` (API keys, shell hooks, state/file handling audit).

## Architecture

```
CLI          exe/lingo, lib/locallingo/cli.rb (arg parsing, command dispatch)
Manager      lib/locallingo/manager.rb (orchestrates status/translate/validate/accept-edits/sync)
State        lib/locallingo/state_store.rb (per-namespace drift state under .i18n-state/)
Providers    lib/locallingo/providers/ruby_llm.rb (LLM translation calls)
Validators   lib/locallingo/validators/ (missing, outdated, duplicate_values, manual_edits)
Quality      lib/locallingo/quality_checker.rb, lib/locallingo/quality/ (static_rules, terminology, british_spellings)
Config       lib/locallingo/configuration.rb, settings.rb (.locallingo.yml + .locallingo.rb)
Helpers      lib/locallingo/json_extraction.rb, key_flattener.rb, reporter.rb
RuboCop      lib/rubocop/cop/locallingo/ (RelativeI18nKey, StrftimeInView), config/default.yml
```

## Key Design Decisions

- **Drift detection via CRC32 source hashes** (`StateStore.hash`) — only genuinely missing/outdated keys are re-translated
- **State split per top-level namespace and locale** (`accounts.de.json`, …) so diffs stay small and reviewable
- **`manual: true` + `target_hash`** protect hand-edited translations from being overwritten; `lingo accept-edits` stamps them
- **Corrupted state raises** instead of being silently reset — state loss is worse than a failed run
- **Everything app-specific is config** — locales, provider/model, context/glossary, language guides, validators, strict tiers, after-translate hooks
- **API keys are lazy** — String or callable via `Locallingo.configure`; a configure key wins over RubyLLM config, which wins over ENV

## Testing Notes

- Specs live in `spec/locallingo/`; shared fixtures in `spec/support/locale_fixtures.rb` (`with_app`, `write_state`, `read_state`)
- Mock the LLM provider — specs must never make network calls; assert on the prompt/payload shape, not provider internals
- Unit specs for Configuration/Settings/KeyFlattener; `StateStore` specs use `Dir.mktmpdir`; Manager workflows use `with_app`; CLI specs cover `Locallingo::CLI` parsing and dispatch; cops use `rubocop-rspec` cop specs
- CI runs `bundle exec rake` on multiple Ruby versions; both rspec and rubocop must pass

## Labels

Every pull request carries exactly one `type` label and at least one `area`
label from `.github/labels.yml` — never a `status` label. `/flow:plan` labels the
issue, `/flow:lfg` copies the issue's `type` and `area` labels onto the PR (never
`plan` or another status label). Without an issue, the type comes from the
change's conventional-commit prefix and the areas from
`bin/labels infer $(git diff --name-only origin/main...HEAD)`. Labels change in
the manifest and reach GitHub with `bin/labels sync`, never through the UI.
Rules: `.github/LABELS.md`. `bin/labels` + `.github/LABELS.md` are the shared
labels kit (canonical copy in docs-kit): never edit them in place.

## Workflow

- **Verify:** `bundle exec rake` (rspec + rubocop, what CI runs) · `bundle exec rake build` when the gemspec changes; never root rubocop on `docs/`
- **Specs:** fast loop `bundle exec rspec spec/locallingo/<file>_spec.rb`; full suite `bundle exec rspec`; two worktrees at once: yes (no database or ports)
- **CI:** required `conformance / Conformance settings`, `conformance / Conformance (Ruby 4.0)` (ruleset `main`); jobs `rake (Ruby 3.2|3.3|3.4|4.0)`, conformance; full suite on the PR; failure report none
- **Review bot:** cubic
- **Merge:** squash — `gh pr merge <PR> --squash --delete-branch`
- **PR contract:** `## Summary`, `## Test plan`; labels per Labels above; no screenshot rule
- **Conflicts:** `CHANGELOG.md` — keep both sides' bullets under one set of subheads; `lib/locallingo/version.rb` — a conflict means the branch bumped on purpose: keep it if the branch's commits say so, else take main's; `docs/bun.lock` — take main's, then `bun install --cwd docs`; `config/default.yml`, `config/locallingo.default.yml` — keep both sides' keys, valid YAML. `docs/` has no PR CI: review its merges by hand
- **Worktree setup:** `bundle install` (`Gemfile.lock` is gitignored); `bun install --cwd docs` only for docs work; undo with `git worktree remove`
- **Release:** `bin/release <v>` (→ `rake release[x.y.z]`, maintainer; PRs never touch `version.rb`); changelog `CHANGELOG.md`, heading `## [X.Y.Z] - YYYY-MM-DD` under `## [Unreleased]`; prep none; lockfiles none tracked; docs `deploy-docs.yml` on release; human none
- **Main health:** `gh run list --branch main --workflow CI --limit 1 --json conclusion --jq '.[0].conclusion'`
- **Upstream:** libraries we own `zoolutions/*`; scrub none
- **Bench:** none

`docs/` is the published documentation site (own bundle, excluded from the gem's rubocop task).
