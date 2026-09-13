# Terminology

The words this repository uses, and what they mean in the code.

- **flat key** — a translation key in dotted form with bracket array indices,
  `accounts.show.title`, `items[0].name`. Produced by `KeyFlattener.flatten` and
  consumed everywhere; the nested hash only exists at YAML read/write time.
- **namespace** — `key.split(".").first`. It decides which state file a key
  lands in (`StateStore#save`) and which locale file a translation is merged
  into (`Manager#merge_translations`). It is derived from the key, never from
  the file name, so a key inside `config/locales/en.yml` still routes to
  `<its-first-segment>.<locale>.json`.
- **source locale** — `config.source_locale` (default `en`): the locale
  translations are authored in and translated *from*.
- **target locale** — an entry of `config.target_locales`: a locale Locallingo
  fills in.
- **drift state / state** — the JSON under `state_dir` (default `.i18n-state/`).
  One file per namespace *and* locale: `accounts.de.json`. An entry is
  `{"source_hash" => ..., "target_hash" => ..., "manual" => true}`, the last two
  optional.
- **source_hash** — `StateStore.hash` (8 hex chars, `Zlib.crc32`) of the source
  value the key was last translated from. The drift fingerprint.
- **target_hash** — the same hash over the *target* value Locallingo wrote, so a
  later hand edit is detectable.
- **manual flag** — `"manual" => true` on a state entry: the target value is
  hand-curated. Set only by `accept_edits!`; cleared by nothing.
- **outdated** — the stored `source_hash` exists and differs from the current
  source value's hash (`Validators::Outdated#outdated_keys`). A key with *no*
  state entry is not outdated.
- **missing** — present in the source hash, absent from the target hash
  (`Validators::Missing#call`).
- **violation** — a Hash `{type:, locale:, key:, suggestion:}` returned by a
  validator. The four types are `:missing`, `:outdated`, `:duplicate_value`,
  `:manual_edit` (the four keys of `Reporter::TYPE_ICONS`).
- **suggestion (quality)** — a different shape entirely: a Hash with
  `key:, text:, locale:, category:, issue:, severity:, source:` and, when
  auto-fixable, `fix: { from:, to: }`. Produced by `QualityChecker`.
- **fixable** — a quality suggestion carrying `:fix`. Only
  `Quality::StaticRules.universal_fixes` and `Quality::BritishSpellings.check`
  emit one, so only those are rewritten by `fix-quality`.
- **strict tier** — `strict` or `strict_all` under the config's `strict:` block:
  the list of violation *types* that make `validate` exit 1 under `--strict` /
  `--strict-all` (`Reporter#exit_code`).
- **validator** — one of the four classes in `lib/locallingo/validators/`, each
  gated by `config.validator_enabled?(name)`.
- **package** — an entry of the config's `packages:` list, keyed by `path`. With
  `--package engines/billing`, that entry deep-merges over `defaults` and
  `base_path` becomes `<root>/engines/billing`.
- **exceptions** — `<state_dir>/exceptions/<locale>.yml`, a flat-loadable YAML
  of keys `translate` must not touch. Read by `Manager#load_exceptions`; it has
  no config key and is not mentioned in the README or the docs site.
- **setup file** — `.locallingo.rb` at the project root, `load`ed by the CLI
  before dispatch so a standalone run can call `Locallingo.configure`.
- **legacy flag** — one of the eight `--status`/`--translate`/… forms in
  `CLI::LEGACY_FLAGS`, accepted only in first position and answered with a
  `[deprecated]` line on stderr.
