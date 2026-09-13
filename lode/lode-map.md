# Lode map

The index of this repository's durable memory. Read this first; it beats a
directory listing. Every file describes the system as it is now, with the
reasoning; `../CHANGELOG.md` records what changed.

- `summary.md` — what Locallingo is, the offline/LLM split, the three invariants
- `terminology.md` — flat key, namespace, drift state, source_hash, target_hash,
  the manual flag, violation vs suggestion, strict tier, package, exceptions
- `practices.md` — practices `../.claude/rules/` does not state: the three
  questions every state writer answers, the duplicated loader, what `--dry-run`
  means here, the failure directions already chosen
- `workflow.md` — the profile the shared `/lode:*` workflow skills read:
  commands, branch and PR rules, layers, input shapes, wrong-here suggestions,
  docs mapping, CI, flake sources, conflict rules, verification
- `plans/README.md` — plans are GitHub issues; `docs/plans/` does not exist yet

## Subsystems

- `cli/summary.md` — `exe/lingo`, `CLI` and `Reporter`: the order of `run`, the
  three command-resolution paths (and why a subcommand after an option is
  ignored), all 13 options, what each command prints and writes, every exit
  code, and the state dir even read-only commands create
- `translation/summary.md` — `Manager` and `KeyFlattener`: loading and merging
  locale YAML, the policy that decides what gets translated, the three-layer
  batch retry, and which writer may touch which state field
- `state-and-validators/summary.md` — `StateStore`'s save rules and corruption
  behaviour, the four validators and their inputs, and the protection invariant
  end to end
- `config-and-providers/summary.md` — `Configuration`'s three-way merge and
  typed readers, `Settings`, `Providers::RubyLLM`'s credential chain, and
  `JsonExtraction`'s four strategies
- `quality/summary.md` — `QualityChecker`'s five check sources, the rule and
  terminology constants with their counts, the random AI sample, and the blast
  radius of `fix!`
- `rubocop-cops/summary.md` — the two shipped cops, why `rubocop` is a
  development dependency, and the flag-but-don't-guess autocorrect rule
- `testing-and-ci/summary.md` — every spec file and what it covers, the two
  support fixtures, the workflows, and `rake release`
- `docs-site/summary.md` — the docs-kit app: the registry rule, the 16 pages
  mapped to the behaviour each documents, the tooling, the deploy

## Review rules (`review/`)

Accepted review findings rewritten as rules about the system and verified
against the code. `/lode:gate` reads every file here before reviewing a diff;
`/lode:learn` adds to them.

- `review/commands-and-docs.md` — five rules and one *Not a bug*: the
  branch-switch guard's single home, the `bundler-audit` install note, the Ruby
  floor matching the gemspec, `gh` plus `allowed-tools` in the PR-review command,
  `--body-file` for any fenced issue or PR body, and the generated
  `tailwind.sources.css` (rejected on purpose)

## Not memory

- `tmp/` — git-ignored: gate diffs and reports, handovers, scratch
