# Quality linting

`Locallingo::QualityChecker` (`lib/locallingo/quality_checker.rb`, 207 lines)
plus the three modules under `lib/locallingo/quality/`. Unlike the translation
side, nothing here touches the drift state: quality reads locale files and
writes locale files.

## 1. What a check produces

`check(locale:, use_ai:)` (`35-42`) loads the locale (defaulting to
`config.source_locale`), runs `check_text` over every key, and appends an AI
pass when asked. `check_text` (`96-104`) runs five sources in this fixed order:

1. `Quality::StaticRules.universal_fixes` — auto-fixable
2. `Quality::StaticRules.check` — the regex rules
3. `@terminology.check` — the configured term list
4. `Quality::BritishSpellings.check` — auto-fixable, **only when
   `quality.british_spellings` is true and the locale being checked equals
   `config.source_locale`** (`british_spellings_for?`, `106-108`)
5. a length heuristic — one `category: :length, severity: :info` suggestion when
   `text.length > LONG_TEXT_THRESHOLD` (200)

That fifth one is easy to forget: any list of "the static rules" that names only
the four modules is incomplete.

A suggestion is a Hash with `key:, text:, locale:, category:, issue:,
severity:, source:`; `match:` on everything but the length heuristic; and `fix:
{from:, to:}` on the auto-fixable ones only. `source:` is `:static` or `:ai`.

## 2. `StaticRules` (`quality/static_rules.rb`, 97 lines)

`RULES` is 5 categories holding 20 regexes in total — terminology 4,
placeholders 2, clarity 6, business 5, accessibility 3. Severity is assigned by
category, not per rule (`severity_for_category`, `88-94`): `:placeholders` is
`:error`, `:terminology` and `:accessibility` are `:warning`, everything else
(including `:length` and `:grammar`) is `:info`.

`UNIVERSAL_FIXES` is 2 entries — `"can not" => "cannot"` and
`"Can not" => "Cannot"` — matched with a case-**sensitive** `text.include?`, and
emitted with `category: :grammar, severity: :warning`. Because the terminology
rule `/\bcan not\b/i` also fires on the same text, one `can not` produces two
suggestions, one of them fixable. That is visible in the CLI output and is not a
bug.

## 3. `BritishSpellings` (`quality/british_spellings.rb`, 45 lines)

14 American→British pairs, each matched `/\b<american>\b/i` and emitted as a
`:warning` with a `fix:`. Source-locale only, opt-in.

## 4. `Terminology` (`quality/terminology.rb`, 78 lines)

A term maps to a suggestion String, or to `nil` meaning "reviewed and
acceptable" — `check` (`49-63`) skips the nil ones, so a list's size is not its
flag count. `BUSINESS` holds 14 terms of which 4 are flagged; `BANKING` is
`BUSINESS` plus 4 more always-acceptable regulatory terms, 18 terms and the same
4 flagged. `BUILTINS` names three settings: `business`, `banking`, `none`.

`resolve` (`67-75`): nil setting → `BUSINESS`; a builtin name → that list; any
other value is treated as a path expanded against `base_path` and loaded with
`YAML.safe_load_file`, and a path that does not exist raises
`Locallingo::Error, "Unknown terminology <x> (not a builtin or a file)"`.
Matching is `text.downcase.include?(term.downcase)` — substring, not word
boundary, so `"transaction"` would match inside `"transactional"` if it were a
flagged term.

## 5. The AI pass

`suggest_improvements` (`72-92`) warns `⚠️  No LLM credentials — skipping AI
suggestions` and returns `[]` when `credentials?` is false, and rescues
`StandardError` into `⚠️  AI suggestion failed: <message>` + `[]` — the AI pass
can never fail the command. Each returned entry is symbolised and defaults
`severity` to `:info`.

`ai_sample` (`119-123`) takes `translations.to_a.sample([size, 100].min).to_h` —
**a random sample capped at 100 keys**, so two `quality --ai` runs on the same
files return different AI suggestions, and a locale with more than 100 keys is
never fully reviewed.

## 6. `fix!` and its blast radius

`fix!` (`57-69`) re-runs `check(locale:)` *without* AI, keeps the suggestions
carrying `:fix`, and returns `{ fixed: <changed file count>, skipped:
<non-fixable suggestion count> }`. Note the asymmetry the CLI prints verbatim:
`fixed` counts **files**, `skipped` counts **suggestions**.

`apply_fixes` (`125-141`) iterates every `**/*.<locale>.yml` under
`locales_dir` and, for each fixable suggestion whose `:text` appears anywhere in
the file's raw text, replaces **every occurrence of that text** with the
case-preserving correction (`content.gsub(suggestion[:text], fixed_text)`).
Two properties follow, and both matter:

- The rewrite is done on the file's raw bytes, not on the parsed YAML, so
  comments and formatting survive — and so does the risk that a value appearing
  under two keys is fixed in both, including one that was never flagged.
- `apply_case_preserving_fix` (`143-150`) matches `/\b<from>\b/i` and picks
  upcase / capitalize / as-written from the match, so `CAN NOT` becomes
  `CANNOT`.

Files are written only when their content actually changed, and not at all under
`--dry-run`; the "Would fix"/"Fixed" log line is emitted either way.

## See also

- `../cli/summary.md` — `quality` and `fix-quality` output
- `../config-and-providers/summary.md` — `quality.model`, credentials
