# Practices

The binding rules are `../CLAUDE.md` and `../.claude/rules/`
([coding-style](../.claude/rules/coding-style.md),
[git-workflow](../.claude/rules/git-workflow.md),
[testing](../.claude/rules/testing.md),
[agents](../.claude/rules/agents.md)). This file adds only what they do not
state. Specific accepted review findings live in `review/`.

## State is the thing that cannot be rebuilt

A locale file can be re-translated; `.i18n-state/` cannot be reconstructed from
anything but the files themselves plus history. Every change to a state writer
answers three questions before it is written:

- Does an existing `manual: true` survive it? (Nothing clears the flag.)
- Does an existing `target_hash` survive it unrecomputed? (`||=`, never `=`.)
- Is the write skipped when the bytes are identical, and newline-terminated?

`StateStore#save` is where the last one lives; `Manager#update_locale_state` and
`#sync_locale_state` are where the first two live. A new writer joins that list
and belongs in `state-and-validators/summary.md`'s table of writers.

## Two loaders, one behaviour

`Manager#load_locale_translations` and
`QualityChecker#load_locale_translations` are byte-identical (verified with
`diff`). Changing the glob patterns, the `content[locale]` guard or the
String-only filter in one and not the other silently gives `quality` a different
view of the files than `translate`. Fix both, or extract.

## The flat key is the contract

Everything downstream of `KeyFlattener.flatten` assumes dotted keys with bracket
indices, and the *first dotted segment* is the namespace that decides both the
state file and the locale file a translation lands in. A change to the flatten
or parse algorithm is a change to file layout, not a refactor.

## Deciding what an operation does under `--dry-run`

`--dry-run` in this codebase means "skip the writes", not "skip the work". A
`translate --dry-run` still calls the model and still costs tokens; a
`sync --dry-run` returns the state already on disk rather than the projected
state. When adding a flag or a command, say which of the two it is, in the
command's own doc page, rather than letting the reader assume "preview".

## Failure directions already chosen

Worth knowing before changing an error path, because each was decided on
purpose:

- Corrupted state **raises**; it is never reset.
- An unreadable `exceptions/<locale>.yml` is **swallowed** into `{}` with a warn
  log — the opt-out file must not stop a run.
- An exhausted translation batch **returns `{}`** and the keys are reported as
  failed; the command still exits 0.
- A failing `after_translate` hook is **not detected at all** (`system`'s return
  value is discarded).
- The AI quality pass **warns and returns `[]`** on any error, including missing
  credentials; `translate` instead raises `MissingCredentialsError`.

## Prose

- Every user-facing fact lives on the CLI reference page *and* the page that
  teaches the behaviour (`docs-site/summary.md` has the page-to-behaviour map).
  Grep the docs for the subject before finishing a change.
- A list in the docs that mirrors a constant (providers, static-rule categories,
  legacy flags, validators) is a completeness claim — open the constant and
  count before editing the list.
- Transcripts and suggestion strings in docs are the exact strings the code
  prints, including the emoji.

## Review

- A review-bot finding is evaluated against the code, not accepted by default;
  a rejection is recorded as a `Not a bug:` entry in `review/` so the next
  reviewer does not raise it again.
- Every accepted finding becomes a rule in `review/` in the same PR
  (`/lode:learn`).
