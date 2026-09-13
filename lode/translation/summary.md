# Translation engine: `manager.rb` and `key_flattener.rb`

`Locallingo::Manager` (`lib/locallingo/manager.rb`, 424 lines — the largest file
in the gem) orchestrates every locale-file operation. It owns a `Configuration`,
a `StateStore`, a `Providers::RubyLLM` and a `Logger`, all built in `#initialize`
(`manager.rb:34-43`).

## 1. Reading and writing locale files

`load_locale_translations` (`manager.rb:376-395`) globs two patterns under
`config.locales_dir` — `**/*.<locale>.yml` then `<locale>.yml` — loads each with
`YAML.load_file`, skips anything whose top-level `[locale]` key is absent, and
merges `KeyFlattener.flatten(content[locale])` into one flat hash. **Only String
values survive** (`translations[key] = value if value.is_a?(String)`), so an
integer or boolean leaf is invisible to every command. Later files win on a key
collision, in glob order.

`QualityChecker#load_locale_translations` (`quality_checker.rb:177-196`) is a
byte-for-byte copy of this method. Changing one and not the other is the
classic bug here.

Writing back is `merge_translations` (`manager.rb:359-367`): group the translated
pairs by namespace, find the file with `find_or_create_locale_file`
(`manager.rb:369-372` — `Dir.glob("**/<namespace>.<locale>.yml").min`, else
`<locales_dir>/<namespace>.<locale>.yml`), `YAML.load_file` it, set each key with
`KeyFlattener.set_nested_value`, and `File.write(file, existing.to_yaml)`. That
rewrites the whole file through Psych, which is why the shipped default
`after_translate` hook is `bundle exec i18n-tasks normalize -p`.

`KeyFlattener` (`key_flattener.rb`, 114 lines) is the only place the nested↔flat
conversion lives. `flatten` (`17-37`) indexes arrays as `key[0]`, recurses into
hashes inside arrays as `key[0].sub`, and **drops array items that are neither
String nor Hash**. `parse_key_segments` (`62-88`) reverses that, including
consecutive indices (`matrix[0][1]`); `navigate_or_create` (`92-108`) creates the
intermediate hashes and arrays, padding arrays with `nil`.

## 2. The seven public operations

| Method | Lines | Reads | Writes |
|---|---|---|---|
| `status` | `46-64` | source + each target + each target's state | nothing |
| `validate` | `68-88` | same | nothing |
| `translate!` | `91-98` | same, plus exceptions | locale YAML + state |
| `accept_edits!` | `106-130` | same | state |
| `sync_state!` | `143-156` | source + each target + all state | state |
| `source_hash` | `133-135` | source | nothing |
| `run_after_translate_hooks` | `159-164` | config | whatever the hooks do |

`status` reports `outdated` through `outdated_validator.outdated_keys`
regardless of `validators.outdated` — the config gate applies to `validate`
(`manager.rb:79-81`), not to `status`. `validate` gates all four validators,
runs `DuplicateValues` once over the source only, and the other three per target
locale.

`run_after_translate_hooks` shells out with bare `system(command)` inside
`Dir.chdir(config.root_path)`; **the return value is discarded**, so a failing
hook does not fail the run and is not reported. The commands come from
`.locallingo.yml`, which is app-author-controlled, never from translated text.

## 3. How `translate` decides what to send

`determine_keys_to_translate` (`manager.rb:332-341`) is the whole policy:

```
manual_keys = state entries with "manual" => truthy
force:       source.keys - manual_keys              # exceptions ignored
force_keys:  force_keys & source.keys               # manual keys included
default:     (missing + outdated) - exceptions - manual_keys
```

Three consequences worth holding on to: `--force` respects the manual flag but
**not** the exceptions file; `--force-key` respects neither, and is the only way
to retranslate a protected key; and a key with no state entry is never
*outdated*, only ever *missing*.

Exceptions come from `load_exceptions` (`manager.rb:397-408`) reading
`<state_dir>/exceptions/<locale>.yml` and flattening `content[locale]`. It
rescues `StandardError` into `{}` with a warn-level log line — the one place in
the gem that swallows an error, on the grounds that an unreadable opt-out file
should not stop a translate run.

## 4. The batch loop and its retries

Three nested layers, each with its own budget (`MAX_RETRIES = 3`,
`MAX_MISSING_RETRIES = 2`, `BASE_SLEEP_DURATION = 1.0`):

1. `translate_keys` (`259-276`) slices the keys by `config.batch_size` and
   sleeps 1s between slices. A key the model answered with a missing or empty
   value goes on `failed`.
2. `translate_batch` (`278-301`) makes the call. It rescues `StandardError`,
   sleeps `1.0 * 2**retries` and retries up to 3 attempts, then logs
   `Translation batch failed after 3 retries` at error level and **returns `{}`**
   — so an exhausted batch becomes "every key in it failed", not an exception.
3. `translate_with_missing_retries` (`239-257`) re-sends the failed keys up to
   twice, sleeping `1.0 * 2**round` first, then logs each still-failing key at
   warn level.

`translate_locale` (`213-237`) then writes only `translated.except(*failed)`.
A locale where everything failed still prints `Completed <locale>: 0 translated,
<n> failed` and exits 0 — a failed translation is a log line, not an exit code.

The prompt is built per locale by `translation_prompt` (`303-318`) from
`config.language_name`, `config.context`, `config.placeholder_style`, the
glossary and the per-locale language guide, and it ends by demanding a raw JSON
object with no fences — which is why `JsonExtraction` exists
(`../config-and-providers/summary.md`).

## 5. State updates: who may write what

- `update_locale_state` (`343-357`), after a successful translate: writes
  `source_hash` and `target_hash` fresh, and re-adds `"manual" => true` **only
  if the existing entry had it**. A `--force-key` on a protected key therefore
  replaces the value but keeps the protection.
- `sync_locale_state` (`171-189`), for each target: refreshes `source_hash` for
  every key present in both source and target, sets `target_hash` with `||=`
  (backfill only — never recompute), and deletes entries whose key is absent
  from the *target* file. The source locale's own state (`143-156`) is refreshed
  and pruned against the source file.
- `accept_edits!` (`106-130`): the only writer of `"manual" => true`. It builds
  a plan per locale first, calls `ensure_keys_matched!` (`203-211`) so an
  explicit `--key` that matched nothing anywhere raises `Locallingo::Error`, and
  only then writes.

`keys_to_accept` (`191-201`) has three modes, checked in this order:
`keys:` (any named key present in both source and target, drifted or not),
`all:` (every target key present in the source), and the default — target keys
whose entry is a Hash, not already `manual`, and whose stored `target_hash`
exists *and* differs from the current value's hash. An entry with no
`target_hash` is invisible to the default mode, which is what `sync`'s backfill
exists to fix.

Every state writer inside `Manager` is guarded by `unless dry_run` — the four
guards are in `translate_locale` (`230`), `accept_edits!` (`127`), `sync_state!`
(`149`) and `sync_locale_state` (`188`) — so `--dry-run` reaches the provider and
the file reads but never `StateStore#save` or `merge_translations`'s `File.write`.
`run_after_translate_hooks` is the exception: it has no `dry_run` guard of its
own and runs the hooks whenever it is called. Only `CLI#cmd_translate`
(`cli.rb:159-162`) keeps a dry run from calling it, so a programmatic caller that
builds a `Manager.new(dry_run: true)` and calls it directly still shells out.

## See also

- `../state-and-validators/summary.md` — `StateStore` and the four validators
- `../cli/summary.md` — which flag reaches which argument
