# Review rules: agent config and docs

Accepted review findings, rewritten as rules about the repository as it is and
re-verified against the current tree. Every finding this repository has
accepted so far landed on its agent configuration (`CLAUDE.md`, `.claude/`) or
its docs app, not on `lib/` — the gem's own code has never drawn a review
comment.

### The branch-switch guard is stated once, in the workflow profile

- **Rule:** before switching away from the current branch, the procedure stops
  for work that would be left behind — a non-empty `git status --porcelain`, or
  committed-but-unpushed commits — and never stashes silently; and it checks
  that an upstream exists before comparing against it, falling back to `main..`
  when the branch was never pushed. The rule's single home is
  `../workflow.md` → **Branches and PRs**; the local `/lfg` command that used to
  carry it has been retired in favour of `/lode:lfg`, which reads the profile.
- **Holds because:** `git checkout main` succeeds with a dirty tree and with
  unpushed commits, so a workflow that switches unconditionally silently drops
  the work out of the new PR. And `git log @{upstream}..` hard-fails with
  `fatal: no upstream configured` on a branch that was never pushed, which is
  exactly the case where every commit is unpushed — so the existence check has
  to come first or the guard cannot run at all.
- **Safe direction:** stopping to ask is free; a silently abandoned branch is
  discovered later, by someone else.
- **Where:** `../workflow.md` → Branches and PRs
- **Proven by:** no test — it is a procedure, not code
- **Origin:** cubic learning 109ba01d (merged from two PR #8 threads,
  `c98ec322` and `e7813ae6`)

### `.claude/commands/security.md` names `bundler-audit` as an external tool with an install step

- **Rule:** the Security Tools section says, in the comment above the command,
  that `bundler-audit` is not a project dependency and must be installed first
  (`gem install bundler-audit`) before `bundle audit check --update`.
- **Holds because:** `bundler-audit` appears in neither `locallingo.gemspec` nor
  the root `Gemfile` — the only Gemfile that carries it is `docs/Gemfile`, for
  the docs app's own `bin/bundler-audit`. An audit step documented as if it were
  bundled errors out on a fresh checkout, and a security workflow that errors
  out gets skipped.
- **Where:** `../../.claude/commands/security.md` (Security Tools)
- **Proven by:** no test — grep `Gemfile` and `locallingo.gemspec` for
  `bundler-audit` and find nothing
- **Origin:** cubic learning 995f36ef; PR #8

### `CLAUDE.md`'s Ruby floor is the gemspec's floor

- **Rule:** the Tech Stack section states `Ruby >= 3.2` with the CI matrix
  `3.2, 3.3, 3.4`, matching `locallingo.gemspec`'s
  `required_ruby_version = ">= 3.2"`, `.rubocop.yml`'s
  `TargetRubyVersion: 3.2` and `ci.yml`'s matrix.
- **Holds because:** `CLAUDE.md` is what steers an agent's syntax choices. A
  floor stated one version too high licenses 3.3-only syntax, which passes
  locally and fails exactly one CI cell — the slowest failure to read.
- **Where:** `../../CLAUDE.md` (Tech Stack); the four sources above
- **Proven by:** no test; CI's 3.2 cell is the backstop
- **Origin:** cubic learning b09e69cf; PR #8

### `.claude/commands/review-pr.md` fetches with `gh` and declares `allowed-tools`

- **Rule:** the PR-review command gets its PR data through `gh pr view`,
  `gh pr diff` and `gh pr checks`, and declares an `allowed-tools:` frontmatter
  list matching its sibling PR commands.
- **Holds because:** this repository configures no MCP server (there is no
  `.mcp.json`), so a command that reached for `mcp__github__*` would fail at its
  first step wherever the GitHub MCP server is not enabled; and a command with no
  `allowed-tools` runs the model with unrestricted tool access, which is not what
  the other PR commands do.
- **Where:** `../../.claude/commands/review-pr.md` (frontmatter, Workflow §1)
- **Proven by:** no test
- **Origin:** cubic learning 9145fb7d; PR #8

### An issue or PR body is written to a file and passed with `--body-file`

- **Rule:** a body that carries code fences is written to a temp file first and
  passed as `gh issue create --body-file <file>` / `gh pr create --body-file
  <file>`. Never an inline heredoc with `--body`. Where the procedure names the
  command, it names the one it is actually running — `gh issue create` for a
  plan, `gh pr create` for a PR.
- **Holds because:** the shell interpolates inside a `"…"` body argument, so
  backticks in a fenced block are executed or eaten and the posted text is not
  the text that was written. Plans and PR bodies in this repository are mostly
  fenced YAML and Ruby, so this is the normal case, not the edge case.
- **Safe direction:** a temp file costs one line and is never wrong.
- **Where:** `../plans/README.md`; `../workflow.md` → Branches and PRs
- **Proven by:** no test — it is a procedure, not code
- **Origin:** merged PR #8 review thread `132a4bce` on the retired
  `.claude/commands/plan.md`, accepted by the maintainer ("applied the
  suggestion") and fixed in `4eff12d`. The command is gone; the rule moved to the
  workflow profile, which `/lode:plan` and `/lode:lfg` read.

### Not a bug: `docs/app/assets/stylesheets/tailwind.sources.css` commits absolute gem paths and a Ruby version

- **Rule:** portability findings about that file — machine-specific
  `/Users/.../.gem/ruby/<version>/gems/...` paths, or a Ruby version that does
  not match `docs/Dockerfile` — are not defects here, and are not to be raised
  again.
- **Holds because:** the file is output, not input. `docs/bin/build-css`
  regenerates it from `bundle show daisyui` and `bundle show docs-kit` on every
  run and aborts if either fails, and `docs/.dockerignore` excludes it from the
  image, so no build ever consumes the committed copy. Gitignoring it instead is
  a fleet-wide docs-kit convention change (generator plus a `--sync` migration),
  tracked at zoolutions/docs-kit#71 — not a one-site edit.
- **Where:** `../../docs/app/assets/stylesheets/tailwind.sources.css`,
  `../../docs/bin/build-css`, `../../docs/.dockerignore`
- **Proven by:** no test
- **Origin:** cubic learning 3398d197; PR #6 (rejected with reasons by the
  maintainer)
