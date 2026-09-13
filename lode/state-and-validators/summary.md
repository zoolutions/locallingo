# Drift state and validators

## 1. `StateStore` (`lib/locallingo/state_store.rb`, 66 lines)

The whole persistence layer. `#initialize` (`18-21`) `mkdir_p`s `state_dir`, so
constructing one has a filesystem side effect.

`StateStore.hash` (`24-26`) is `format("%08x", Zlib.crc32(text.to_s))` — 8 hex
characters. It is a change fingerprint, not a checksum with security properties,
and `Validators::Outdated` and `Validators::ManualEdits` call the class method
directly while `Manager` goes through the instance delegate (`hash`, line 28).

`#load(locale)` (`31-41`) merges every `*.<locale>.json` in `state_dir` into one
hash (later files in glob order win a key collision), and converts a `JSON::ParserError` into
`Locallingo::Error` carrying `"Corrupted state file: … This would cause state
loss. Fix the JSON manually or restore from git."` The error names the parse
problem but **not the file** — the message is the same whichever namespace file
is broken.

`#save(locale, locale_state)` (`46-64`) does three things in order:

1. Regroup the flat state by `key.split(".").first`.
2. For each namespace, build `"#{JSON.pretty_generate(keys.sort.to_h)}\n"` and
   `next if` the file already contains exactly those bytes. This is the
   no-churn rule: keys sorted, pretty-printed, one trailing newline, and an
   unchanged file is not touched at all (its mtime included).
3. Delete every `*.<locale>.json` whose namespace is no longer in the state.
   An empty `locale_state` therefore deletes *all* of that locale's files.

`save` writes with a plain `File.write`, not a write-then-rename — an
interrupted save can leave a truncated JSON file, which the next `load` reports
as corrupted rather than silently dropping.

## 2. The four validators

All live in `lib/locallingo/validators/`, all expose `#call(**)` returning an
array of `{type:, locale:, key:, suggestion:}` hashes, all are gated in
`Manager#validate` by `config.validator_enabled?`. The four types are exactly
the four keys of `Reporter::TYPE_ICONS`.

| Validator | File | Input | Emits | Default |
|---|---|---|---|---|
| `Missing` | `missing.rb` (24) | `source:`, `target:`, `locale:` | `:missing` | on |
| `Outdated` | `outdated.rb` (49) | `source:`, `locale_state:`, `locale:` | `:outdated` | on |
| `DuplicateValues` | `duplicate_values.rb` (42) | `source:` only | `:duplicate_value` | off |
| `ManualEdits` | `manual_edits.rb` (39) | `target:`, `locale_state:`, `locale:` | `:manual_edit` | off |

**`Missing`** is `source.keys - target.keys`; the suggestion is
`Run: lingo translate --locale <locale>`.

**`Outdated`** keys off `outdated_keys` (`outdated.rb:28-33`):
`stored = locale_state.dig(key, "source_hash"); key if stored && stored != hash`.
The `stored &&` is why a key with no state entry is never outdated. Its
suggestion branches on the `manual` flag (`suggestion_for`, `39-46`): a curated
key is told to update the value by hand and re-run `accept-edits`, never to
`--force-key` over it.

**`DuplicateValues`** groups the source's `activerecord.attributes.*` keys by
value, then reports any key whose value matches one of them — skipping every key
under `activerecord.` (`AR_PREFIX`, not just the attributes prefix), because
Rails owns that namespace and a model name equal to an attribute label is
intentional. It hard-codes `locale: "en"` in the violation rather than reading
`config.source_locale`, so an app whose source locale is not `en` gets the wrong
locale label on this violation type only.

**`ManualEdits`** reports a target key whose entry is a Hash, is not already
`manual`, has a `target_hash`, and whose current value hashes differently. Its
suggestion is the exact command to run:
`lingo accept-edits --locale <locale> --key <key>`.

Three of the four take `cli_name:` in the constructor so the suggestion text
names whatever binary invoked them; `DuplicateValues` takes no constructor
argument because its suggestion names keys, not commands.

## 3. The protection invariant, end to end

A key is protected when its state entry carries `"manual" => true`. The complete
set of writers and what each does to it:

| Writer | `manual` |
|---|---|
| `Manager#accept_edits!` | sets it |
| `Manager#update_locale_state` | re-adds it if it was already there |
| `Manager#sync_locale_state` | copies the existing entry (`existing.dup`) and only touches `source_hash` / backfills `target_hash` |
| `StateStore#save` | serialises whatever it is handed |

Nothing clears it. `Manager#determine_keys_to_translate` reads it to exclude
protected keys from both the default path and `--force`; only `--force-key`
translates one, and `update_locale_state` puts the flag straight back.

The second half of the invariant is `target_hash`: `sync_locale_state` sets it
with `||=`, so a sync backfills a baseline for a hand-added translation but can
never absorb the drift of one that already had a baseline.

## See also

- `../translation/summary.md` — the Manager paths that call these
- `../review/commands-and-docs.md` — accepted review rules
