# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- The translation prompt asks for natural, idiomatic text in the target
  language ("into natural, idiomatic German") instead of a word-for-word
  translation: the meaning, phrasing and UI conventions a native speaker would
  use, with idioms replaced by their local equivalent. Only newly translated or
  outdated keys are affected; run `lingo translate --force` to redo the rest.
  The source language is now named too (`en` → "English").
- The translation prompt no longer hardcodes "Use formal business language".
  Register (formal "Sie"/"Lei" vs. informal "du"/"tu") belongs in each
  locale's `language_guides` entry; add it there to keep a formal tone.
- `lingo translate` exits `1` when any key fails to translate, and prints
  `⚠️ Translation finished: N keys failed` with the failed keys instead of
  `✅ Translation complete!`. Translated keys are still written and the
  `after_translate` hooks still run; `--dry-run` reports failures but exits `0`.
  Appending `|| true` restores the old always-`0` behaviour, but also hides
  every other failure (missing credentials, a broken config). (#25)
- `Manager#translate!` returns `{ locale => failed_keys }`. (#25)
- Allow `ruby_llm` 2.x (dependency constraint widened from `< 2` to `< 3`). The
  gem only uses RubyLLM's stable chat API and guarded config accessors, so a
  host app can take the RubyLLM 2.0 bump without waiting on Locallingo.

### Fixed
- One invalid value in a model reply (e.g. typographic quotes returned as
  unescaped `"`) no longer fails every key in its batch. A reply that cannot be
  parsed is never resent as-is: the batch is split in half, down to single keys,
  so only the bad key fails. Transport errors still retry with backoff. (#25)
- When a ```json fence holds invalid JSON, the parse error now names the line
  and column inside the fence instead of the fence at line 1. (#25)
- The translation prompt asks the model to escape `"` inside values as `\"`
  and keep typographic quotes (“ ” „ ‚ « ») as they appear in the source. (#25)
- State files are written with a trailing final newline, so the output is
  POSIX-conformant and files that already end with a newline are no longer
  rewritten with newline-only diffs. One-time effect after upgrading: each
  state file gets a single newline-adding rewrite, then stabilizes. (#7)
- `lingo sync` backfills a missing `target_hash` from the current target value,
  so hand-added translations (written straight into the YAML, never passing
  through `translate` or `accept-edits`) get a baseline and the `manual_edits`
  validator can watch them. An existing `target_hash` is still never
  recomputed — that would silently absorb hand-edit drift.

### Fixed (0.4.0)
- `lingo sync` no longer destroys hand-edit protection: it now only refreshes
  each entry's `source_hash` and preserves `target_hash` and `manual: true`
  (the pre-extraction `bin/translate` behavior). Previously a single sync wiped
  both fields for every key, blinding the `manual_edits` validator and causing
  `manual` flags to flip back and forth across branches.
- `translate --force-key` on a `manual`-flagged key keeps the flag. The value is
  still retranslated on explicit request, but no command removes `manual: true`
  anymore — unprotecting a key requires editing the state JSON by hand.
- State files whose content is unchanged are no longer rewritten, so operations
  never touch `.i18n-state/` files for unrelated namespaces.

### Changed
- Unscoped `lingo accept-edits` now accepts only the keys the `manual_edits`
  validator flags (actually hand-edited), instead of stamping `manual: true` on
  every key of the locale. Use the new `--key KEY` (repeatable) for surgical
  accepts, or `--all` for the old blanket behavior (initial adoption).
- Validator suggestions are scoped and safe to follow verbatim: `manual_edit`
  violations suggest `accept-edits --locale <l> --key <key>`, and `outdated`
  violations on manual keys tell you to update the value by hand and re-accept
  it rather than force-translating over curated text.

### Added
- `Locallingo.configure { |c| c.anthropic_api_key = ... }` — gem-level provider
  credentials as Strings or lazy callables, for apps whose keys don't live in
  ENV (Rails credentials, app config objects, vaults). Precedence:
  `Locallingo.configure` → host `RubyLLM.configure` → ENV.
- `.locallingo.rb` setup file: the CLI loads it from the project root before
  dispatch, so standalone `lingo` runs can configure credentials without
  booting Rails.
- Initial extraction from the `bin/translate` toolchain into a standalone gem.
- `lingo` CLI with subcommands: `status`, `translate`, `validate`, `quality`,
  `fix-quality`, `accept-edits`, `hash`, `sync`. Legacy `--flag` forms still work
  and print a deprecation notice.
- `Locallingo::Configuration` — `.locallingo.yml` with a `defaults:` block plus
  optional per-`packages:` overrides (deep-merged, ERB-evaluated).
- Provider-agnostic translation via RubyLLM (`provider:`/`model:` config).
- Validators (config-gated): `missing`, `outdated`, `duplicate_values`,
  `manual_edits`.
- Quality checks: static rules, universal fixes, configurable terminology lists
  (`business`/`banking`/custom), optional British-spelling drift, plus an
  optional AI review pass.
- Source-hash drift detection with per-namespace state files under `.i18n-state/`.
- Configurable `after_translate` hook commands (e.g. `i18n-tasks normalize -p`,
  `rails i18n:export`).
- RuboCop cops `Locallingo/RelativeI18nKey` (with autocorrect) and
  `Locallingo/StrftimeInView`, loaded via `require: locallingo/rubocop`.
