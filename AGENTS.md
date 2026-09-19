# Locallingo

Project instructions for every agent: Claude Code (`CLAUDE.md` imports this file), Grok, Cursor,
Copilot, Codex read it directly. Claude-only extras (commands, rules) live under `.claude/`.

AI-assisted i18n translation, drift detection, and quality linting on top of
i18n-tasks — packaged as a gem (ships the `lingo` CLI).

## Tech Stack

- **Ruby**: >= 3.2 (CI matrix: 3.2, 3.3, 3.4)
- **Translation**: RubyLLM (OpenAI, Anthropic, Google, … — provider-agnostic)
- **i18n plumbing**: i18n-tasks
- **Testing**: RSpec + SimpleCov
- **Linting**: RuboCop (the gem also ships its own cops)

## Critical Rules

### Never Do
1. **NO version bumps in PRs** — `rake release[x.y.z]` owns `version.rb`; PRs must not touch it
2. **NO storing or logging API keys** — keys come from ENV, `Locallingo.configure`, or `RubyLLM.configure`; never persist them
3. **NO dropping `manual` flags from state** — sync is non-destructive; hand-edit protection must survive every state rewrite
4. **NO rewriting unchanged state files** — `StateStore#save` skips byte-identical files so diffs stay small; keep it that way
5. **NO state files without a trailing final newline** — writer output must be POSIX-conformant and idempotent

### Always Do
1. **TDD**: Write tests BEFORE implementation
2. **State safety first**: state corruption raises (`Locallingo::Error`) rather than silently losing drift data
3. **Config-driven behavior**: anything app-specific belongs in `.locallingo.yml` (`defaults` + per-`packages` overrides), never hardcoded
4. **Backwards compatibility**: legacy CLI flag forms (`lingo --translate`, …) keep working with a deprecation notice

## Commands

```bash
bundle exec rspec          # Run tests
bundle exec rake rubocop   # Lint (scoped to exe/lib/spec/Rakefile/Gemfile/gemspec)
bundle exec rake           # Both — this is what CI runs
bundle exec rake build     # Build gem and verify contents
rake release[x.y.z]        # Release (version bump + tag + push) — maintainer only
```

Command output is condensed by rtk (PreToolUse hook). `.rtk/filters.toml` covers this repo's
`rake` tasks (`bundle exec rake`, `bundle exec rake rubocop` — the Rakefile wraps rspec/rubocop,
so the hook's built-in rspec/rubocop rewrites don't catch them); every edit to it needs
`rtk trust --yes` + `rtk verify`. Write commands in hook-rewritable shapes: no `for`/subshell
wrappers, no `| head` on rtk-handled commands, `bundle exec rubocop` not `bin/rubocop`.

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/lfg` | Full autonomous workflow: branch → understand → explore → plan → TDD → verify → PR |
| `/plan` | Fable-powered planning → GitHub issue or `docs/plans/` markdown (read-only; execute with `/lfg`) |
| `/github-review-comments` | Process unresolved PR review comments |
| `/github-review-failures` | Diagnose and fix failing CI checks on a PR |
| `/github-review-pr` | Full PR review: conflicts → CI failures → review comments |
| `/review-pr` | Review a PR for pattern compliance |
| `/tdd` | Enforce RED → GREEN → REFACTOR cycle |
| `/security` | Security audit (API keys, shell hooks, state/file handling) |

Commands pin a model tier via frontmatter aliases: `sonnet` for pattern-following
implementation, `opus` for orchestration and full PR review, `fable` for
read-only planning (`/plan`). Use aliases, not full model IDs.

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
- Mock the LLM provider — specs must never make network calls
- CI runs `bundle exec rake` on multiple Ruby versions; both rspec and rubocop must pass

## More Documentation

See `.claude/` directory:
- `commands/` — Slash command definitions
- `rules/` — Coding style, git workflow, testing, agents

See `docs/` for the published documentation site (own bundle — excluded from the
gem's rubocop task; don't run root `bundle exec rubocop` against it).
