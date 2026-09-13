# CLI: `cli.rb` and `reporter.rb`

`exe/lingo` is six lines: `require "locallingo"` then
`Locallingo::CLI.start(ARGV)`. Everything below is `lib/locallingo/cli.rb`
(235 lines) and `lib/locallingo/reporter.rb` (147 lines).

## 1. The order of `run`

`CLI#run` (`cli.rb:57-66`) does five things, in this order, and the order is
load-bearing:

1. `resolve_command` (`cli.rb:79-94`) — consumes the leading token.
2. `parse_options!` (`cli.rb:96-100`) — `OptionParser#parse!` over the rest.
3. `load_setup_file` (`cli.rb:72-75`) — `load`s `.locallingo.rb` from `Dir.pwd`
   if it is a file. Absent is fine; an error inside it propagates.
4. `Locallingo.configuration(root_path: Dir.pwd, package: options[:package])`.
5. `dispatch` (`cli.rb:133-149`).

So `--package` must be parsed before the config resolves, and the setup file
runs before any provider is constructed. The whole body is wrapped in
`rescue Locallingo::Error => e`, which prints `❌ <message>` to stderr and
`exit 1` — `MissingCredentialsError` included, since it subclasses `Error`.
Nothing else is rescued: a malformed locale file raises `Psych::SyntaxError` out
of `load_locale_translations` and the process dies with a backtrace (verified).
An unparseable *LLM reply* does not reach here — `Manager#translate_batch` and
`QualityChecker#suggest_improvements` each rescue `StandardError` themselves.

## 2. Command resolution, and the gotcha

`resolve_command` has exactly three paths:

| First token | Result |
|---|---|
| nil | `"status"` |
| a key of `LEGACY_FLAGS` (8 entries) | shift it, warn `[deprecated] \`<flag>\` — use \`lingo <sub>\` instead.`, return the subcommand |
| anything not starting with `-` | shift it and use it as the subcommand |
| anything else starting with `-` | `"status"`, token left for `OptionParser` |

The last row is the gotcha: **a subcommand after an option is ignored.**
`lingo --locale de translate` resolves to `status`, `OptionParser` strips
`--locale de`, and `translate` is left in `@argv` where nothing reads it — the
command runs `status` and exits 0. Verified by running it. A legacy flag is only
recognised in first position for the same reason.

An unknown subcommand reaches `dispatch`'s `else`, which warns
`Unknown command: <cmd>` + `Run \`lingo --help\`.` and exits 1.

## 3. Options

`build_parser` (`cli.rb:102-131`) defines 13 switches. `@options` starts as
`{ format: :text }`.

| Switch | Effect |
|---|---|
| `-l`, `--locale LOCALE` | `:locale` — one target locale |
| `-f`, `--force` | `:force` — re-translate everything except manual keys |
| `--force-key KEY` | appends to `:force_keys` |
| `--key KEY` | appends to `:keys` (accept-edits) |
| `--all` | `:all` (accept-edits) |
| `-v`, `--verbose` | `:verbose` — `Manager#log` also writes to stderr |
| `-n`, `--dry-run` | `:dry_run` |
| `--strict` | `:strict` |
| `--strict-all` | `:strict` **and** `:strict_all` |
| `--ai` | `:use_ai` |
| `--json` | `:format = :json` |
| `--package PATH` | `:package` |
| `-h`, `--help` | prints the banner and `exit 0` |

`--strict-all` implies `--strict`; the reverse is not true, and
`Reporter#exit_code` picks the `:strict_all` tier whenever `strict_all` is set.

## 4. What each command does and prints

`dispatch` builds one `Reporter` and routes to a `cmd_*` method. Every command
constructs its own `Manager` or `QualityChecker` (`cli.rb:227-233`) — no shared
state.

| Command | Method | Prints (verbatim) | Writes |
|---|---|---|---|
| `status` | `cmd_status` `151-153` | `Reporter#status` | `.i18n-state/` + `translation.log` (see §6) |
| `translate` | `cmd_translate` `155-165` | `🔄 Translating...` (verbose only), `📝 Running post-translate hooks...`, `✅ Translation complete!`, `(dry run - no changes made)` | locale YAML + state, unless `--dry-run` |
| `validate` | `cmd_validate` `167-170` | `Reporter#violations`, then `exit(<its return value>)` | nothing beyond §6 |
| `quality` | `cmd_quality` `172-176` | `Reporter#quality` | nothing |
| `fix-quality` | `cmd_fix_quality` `178-185` | `🔧 Fixing quality issues for <locale>...` or `🔍 Checking fixes for <locale>...`, `Fixed: <n> files`, `Skipped: <n> non-fixable suggestions` | locale YAML, unless `--dry-run` |
| `accept-edits` | `cmd_accept_edits` `187-198` | `manual_edits validator is disabled…` (and returns), or `report_accepted`'s lines | state, unless `--dry-run` |
| `hash` | `cmd_hash` `211-214` | the 8-hex fingerprint, or `{"hash":"…"}` under `--json` | nothing |
| `sync` | `cmd_sync` `216-225` | `🔄 Syncing state file…` or `🔍 Would sync state file…`, `State directory: …`, per-locale key counts, `Total tracked keys: <n>` | state, unless `--dry-run` |

Two notes the table cannot carry:

- **`translate --dry-run` still calls the model.** `Manager#translate_locale`
  runs the full batch loop and only skips `merge_translations` /
  `update_locale_state` / `@state.save`; `cmd_translate` additionally skips the
  `after_translate` hooks. It costs tokens and wall time and prints no plan.
- **`sync --dry-run` prints the state that is already on disk.** `sync_state!`
  builds its return value with `@state.load` *after* skipping the saves, so the
  counts are the pre-existing ones, not the projected ones.

`report_accepted` (`cli.rb:200-209`) prints
`Nothing to accept — no hand-edited translations found.` when the total is zero,
else one `  <locale>: <n> key(s)` line per locale with any accepts and
`✅ Marked <n> translation(s) as intentional.`

## 5. Exit codes, in full

- `0` — the default; also `-h/--help`.
- `1` — `validate --strict`/`--strict-all` when a violation of a tier type is
  present (`Reporter#exit_code`, `reporter.rb:66-72`); an unknown subcommand;
  any `Locallingo::Error` (corrupted state, an unknown `--package`, an unknown
  terminology setting, `accept-edits --key` naming a key no locale has, missing
  provider credentials).
- Anything else — an unrescued exception's own exit status.

`validate` without a strict flag prints violations and exits 0 by design.

## 6. Side effects even the read-only commands have

Every command that builds a `Manager` creates `state_dir` twice over —
`StateStore#initialize` `mkdir_p`s it (`state_store.rb:18-21`) and
`Manager#build_logger` (`manager.rb:410-417`) `mkdir_p`s it again and opens
`<state_dir>/translation.log` as a rotating `Logger` (5 files, 1 MiB each).
So `lingo status` on a fresh checkout creates `.i18n-state/translation.log`.
Verified by running it. `QualityChecker` takes a `logger:` and never builds one,
so `quality` and `fix-quality` write no log.

## 7. `Reporter`

`Reporter` (`reporter.rb`) owns all text and JSON rendering and the strict exit
code; it writes to an injectable `io` (default `$stdout`) and never exits itself.
`--json` short-circuits each of `#status`, `#violations`, `#quality` to
`JSON.pretty_generate` of the raw structure — so the JSON shape *is* the Ruby
shape, symbol keys and all.

Text mode truncates: violations print the first 10 per type with
`   ... and <n> more`; quality prints the first 20 per severity, ordered
`error, warning, info` (`print_quality_by_severity`, `reporter.rb:110-122`), each
with its text truncated to 60 characters. `Manager#status` has already truncated
`missing_keys`/`outdated_keys` to 10 before the reporter sees them.

## See also

- `../translation/summary.md` — what `Manager` does with these options
- `../quality/summary.md` — `quality` / `fix-quality`
- `../config-and-providers/summary.md` — `--package`, `.locallingo.rb`
