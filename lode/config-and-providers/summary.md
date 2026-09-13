# Configuration, settings and the LLM provider

Three files that decide *what* the engine does and *who* it talks to, plus the
parser that survives the answer.

## 1. `Configuration` (`lib/locallingo/configuration.rb`, 161 lines)

Loads `.locallingo.yml` and exposes typed readers, so no other class parses a
raw config hash.

**Resolution** (`resolve`, `113-117`) is three deep merges, in this order:

1. `shipped_defaults` — the `defaults:` block of
   `config/locallingo.default.yml`, found via `DEFAULT_CONFIG_PATH`
   (`File.expand_path("../../config/locallingo.default.yml", __dir__)`).
2. `user_defaults` — the `defaults:` block of the app's config file.
3. `package_overrides` — only when `package:` was passed: the `packages:` entry
   whose `"path"` equals it, minus `"path"`. A `package:` naming no entry raises
   `Locallingo::Error, "No package <path> in <file>"`.

`config_file` (`141-145`) takes the first of `CONFIG_FILENAMES`
(`.locallingo.yml`, `.locallingo.yaml`) that exists at `root_path`. With no file
at all, both user steps return `{}` and the shipped defaults stand alone, so
`Locallingo.configuration` never fails for a missing config.

`load_yaml` (`147-149`) is `YAML.safe_load(ERB.new(File.read(path)).result,
aliases: true)`. Two consequences: the config is **ERB-evaluated**, so
`<%= ENV["…"] %>` works (and arbitrary Ruby in a config file runs), and it is
`safe_load`, so no arbitrary object deserialization.

`deep_merge` (`151-159`) recurses only when both sides are Hashes; an Array value
(like `target_locales`) is replaced wholesale by an override, never concatenated.

**Paths** all hang off `base_path` (`39-41`): `root_path`, or
`root_path/<package>` when scoped. So `locales_dir`, `state_dir`,
`exceptions_dir` (`state_dir/exceptions`) and `log_file`
(`state_dir/translation.log`) all move with `--package`.

**Readers that `fetch` without a default will raise `KeyError` if the shipped
defaults ever stop supplying them**: `source_locale`, `target_locales`,
`locales_dir`, `state_dir`, `provider`. Those with a default —
`context` (`"a business application"`), `placeholder_style`
(`"%<name>s, %<count>s"`), `glossary` (`{}`), `after_translate` (`[]`) — tolerate
a hand-written config file that omits them only because the shipped defaults are
merged in first.

`language_guide(locale)` (`70-77`) returns `""` when unset, the value verbatim
when it is a String, and `File.read` of `guide["file"]` expanded against
`base_path` when it is a Hash with a `"file"` key — returning `""` if that path
does not exist, silently.

`language_name(locale)` (`81-83`) is `BUILTIN_LANGUAGE_NAMES[locale.to_s] ||
locale.to_s`. The map has 12 entries covering 11 distinct languages (`nb` and
`no` both map to `"Norwegian"`), and an unknown locale falls back to its own
code, which then appears verbatim in the prompt.

## 2. `Settings` (`lib/locallingo/settings.rb`, 31 lines)

The credentials half, deliberately separate from the YAML half: keys must never
live in `.locallingo.yml`. `PROVIDERS` is five symbols — `openai`, `anthropic`,
`gemini`, `deepseek`, `openrouter` — and `attr_accessor` generates one
`<provider>_api_key` accessor per entry.

`api_key_for(provider)` (`22-29`) returns nil for a provider outside that list,
calls the value if it responds to `call` (**every time — never memoised**, so a
rotating or lazily-available key works), strips it, and maps blank to nil.

`Locallingo.settings` memoises one instance; `Locallingo.reset_settings!` clears
it and is what the spec suite calls in an `after` hook.

## 3. `Providers::RubyLLM` (`lib/locallingo/providers/ruby_llm.rb`, 127 lines)

The only place the gem touches a model SDK. `CREDENTIAL_ENV` maps the same five
provider symbols to their ENV var names.

**Credential precedence is one chain, stated once** in `resolved_api_key`
(`95-97`): `settings_api_key` (`Locallingo.configure`) → `host_configured_api_key`
(what the app already set through `RubyLLM.configure`, inspected only if
`RubyLLM` is already defined — the class never requires it just to peek) →
`env_api_key`.

- `credentials?` (`38-42`) returns **true for any provider not in
  `CREDENTIAL_ENV`** — an unknown provider is assumed configured elsewhere
  rather than blocked.
- `ensure_credentials!` (`45-53`) raises `MissingCredentialsError` naming the ENV
  var, the `Locallingo.configure` call and the `.locallingo.rb` file.
  `Manager#translate!` calls it first; `QualityChecker#suggest_improvements`
  instead checks `credentials?` and warns-and-skips, so a missing key fails
  `translate` and merely degrades `quality --ai`.
- `chat` (`57-69`) `require`s `ruby_llm` lazily, calls `configure_credentials!`,
  builds a **fresh** `RubyLLM.chat(model:, provider:, assume_model_exists: true)`
  per call so batches share no history, sends the payload as
  `JSON.pretty_generate`, and parses the reply through `JsonExtraction`.
- `configure_credentials!` (`79-91`) pushes the resolved key into
  `RubyLLM.config` because RubyLLM does not read provider keys from ENV itself.
  It is `respond_to?`-guarded on both the reader and the writer, and it returns
  early without overwriting a key the host already set unless
  `Locallingo.configure` supplied one.

No key is ever written to disk, interpolated into a log line, or included in an
error message — `ensure_credentials!` names the *variable*, not a value.

## 4. `JsonExtraction` (`lib/locallingo/json_extraction.rb`, 99 lines)

Recovers the JSON object from a model reply, because not every provider has a
fenceless-JSON mode. `extract_object` (`24-38`) tries four strategies in order:

1. `JSON.parse` of the whole (stripped) string.
2. A fenced block — ` ```json … ``` ` — via `fenced_block` (`49-51`).
3. `first_balanced_object` (`56-68`): every `{` in the text, in turn, as a
   candidate start.
4. `JSON.parse(text)` again, unrescued, so the raised error carries a useful
   message.

A top-level value that parses but is not a Hash (an array, say) raises
`JSON::ParserError, "Expected a top-level JSON object, got <class>"` — both
callers treat the result as key→value.

`balanced_object` (`73-97`) is the careful part: it tracks brace depth while
honouring string literals and backslash escapes, so a `}` inside a translated
string does not close the object. The reason the naive greedy `/\{.*\}/m` is
rejected is written above the module: translation prompts are *about* preserving
`%{placeholder}`s, so a model echoing one in prose is expected, not exotic.

## See also

- `../translation/summary.md` — the prompt these credentials serve
- `../quality/summary.md` — the other caller of `chat`
