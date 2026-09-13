# Locallingo

A development-time Ruby gem that keeps a Rails app's `config/locales/**/*.yml`
translated, and ships the `lingo` CLI (`exe/lingo` → `Locallingo::CLI`) that does
it. Its unit of work is the **flat dotted key** (`accounts.show.title`): every
locale file is flattened on load, compared against the source locale, and written
back nested.

The gem is two halves that share nothing but the `Configuration`:

- **Offline half** — `status`, `validate`, `sync`, `hash`, `accept-edits`,
  `quality` without `--ai`, `fix-quality`, and the two RuboCop cops. No provider
  credentials, no network.
- **LLM half** — `translate` and `quality --ai`. Both go through
  `Locallingo::Providers::RubyLLM`, the single place the gem talks to a model.

What makes a re-run cheap is the **drift state** under `state_dir` (default
`.i18n-state/`): one JSON file per top-level namespace and locale, mapping each
key to the CRC32 of the source value it was translated from, and optionally the
CRC32 of the target value plus a `manual: true` flag. A key whose stored
`source_hash` still matches is skipped; one whose hash moved is *outdated*; one
absent from the target is *missing*.

Three invariants govern every change:

1. **Hand-edit protection is never dropped.** No command clears `manual: true`,
   and no command recomputes a `target_hash` over a value it did not itself
   write: `sync_locale_state` sets it with `||=` (backfill only), and
   `update_locale_state` writes a fresh one only for a translation it just
   merged. `update_locale_state` re-stamps a `manual` flag it found;
   `accept_edits!` is the only writer that sets one. Unprotecting a key means
   editing the state JSON by hand.
2. **State writes are idempotent and newline-terminated.** `StateStore#save`
   writes `"#{JSON.pretty_generate(keys.sort.to_h)}\n"` and skips a namespace
   file whose bytes already match, so an unrelated namespace never churns a diff.
3. **Corrupted state raises, never resets.** `StateStore#load` turns a
   `JSON::ParserError` into `Locallingo::Error` with a "fix it or restore from
   git" message; losing drift state is worse than a failed run.

Around those: everything app-specific is `.locallingo.yml` (`defaults:` plus
optional per-`packages:` overrides, deep-merged over the shipped
`config/locallingo.default.yml`); provider keys are resolved lazily from
`Locallingo.configure` → host `RubyLLM.configure` → ENV and never persisted or
logged; the eight legacy `--flag` CLI forms keep working behind a deprecation
notice, in first position only; and `lib/locallingo/version.rb` moves only in
`rake release[X.Y.Z]`, never in a PR.
