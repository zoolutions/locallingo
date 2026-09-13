# RuboCop cops

Two cops the gem ships for *host apps* to run. They are the one subsystem that
never executes during a `lingo` command.

## 1. How they load

`lib/locallingo/rubocop.rb` (21 lines) is the entry point a host app names in
its `.rubocop.yml` as `require: locallingo/rubocop`. It `require`s `rubocop`
itself and then the two cop files, and defines
`Locallingo::RuboCop::CONFIG_DEFAULT`, the absolute path to
`config/default.yml`, for `inherit_gem`.

This is why `rubocop` is a **development** dependency in the gemspec
(`add_development_dependency "rubocop", ">= 1.75", "< 2"`) and not a runtime one:
nothing on the `lingo` path requires this file, so a host app never pulls
RuboCop into its runtime. The gemspec carries a comment saying exactly that, and
`.rubocop.yml` excludes `locallingo.gemspec` from
`Gemspec/DevelopmentDependencies` so the arrangement survives the linter.

`config/default.yml` (47 lines) ships both cops `Enabled: true` with `Include`
lists and, for the first cop, the default `ScopedDirectories`. It also carries a
commented recommendation to disable `Rails/I18nLazyLookup` and
`Rails/I18nLocaleTexts`, which fight the convention the first cop enforces.

## 2. `Locallingo/RelativeI18nKey` (`lib/rubocop/cop/locallingo/relative_i18n_key.rb`, 99 lines)

Flags `t(".key")` — a relative key relying on Rails' lazy lookup — and
autocorrects to a fully-qualified key.

The node matcher is `(send nil? :t (str $_) ...)`, so it only sees a receiverless
`t` whose first argument is a **string literal**; `I18n.t(".x")` and
`t(some_var)` are invisible to it. `on_send` (`46-57`) then requires
`key.start_with?(".")`.

`lazy_lookup_scope` (`77-91`) mirrors Rails' own scope derivation:

1. Take `processed_source.file_path`, return nil if it is nil.
2. Strip everything through the first `app/`.
3. The first path segment must be in `scoped_directories` — otherwise **return
   nil**.
4. Drop that segment, drop `.rb`, drop a trailing `_controller` or `_mailer`,
   and `tr("/", ".")`.
5. Append `.<enclosing def's method name>` when the node is inside a `def`.

Step 3 is the design decision worth keeping: when the path maps to no known
convention the cop **still reports the offense but performs no correction** —
`qualify` returns nil and the corrector block `next`s. Flag-and-leave-it beats
guessing a wrong key.

`scoped_directories` (`61-65`) reads `cop_config["ScopedDirectories"]` and falls
back to `DEFAULT_SCOPED_DIRECTORIES` (8 entries) when the configured list is
empty, so an app cannot accidentally disable correction by configuring `[]`.

## 3. `Locallingo/StrftimeInView` (`lib/rubocop/cop/locallingo/strftime_in_view.rb`, 51 lines)

Flags any `.strftime` send with `RESTRICT_ON_SEND = %i[strftime]`, offending on
`node.loc.selector` (the method name, not the whole expression). No autocorrect —
the right named format is a judgment call.

One exemption, `in_html_input_context?` (`43-47`): the node has an ancestor
`pair` whose key is `:value`. HTML `datetime-local` input values must follow the
HTML spec, not locale display formatting. The guard is `pair.key.respond_to?(:value)`
before reading it, so a non-literal hash key does not raise.

Scoping is left to the standard `Include`/`Exclude`; `config/default.yml` limits
it to `app/views/**/*.rb` and excludes `app/views/**/*_mailer/**/*.rb`.

## 4. Complexity exemption

`.rubocop.yml` excludes `lib/rubocop/cop/**/*` from `Metrics/CyclomaticComplexity`
and `Metrics/PerceivedComplexity` with the reasoning in a comment: AST walkers
are inherently branchy. The other metric caps (`MethodLength: 35`,
`AbcSize: 45`, `ClassLength: 300`) still apply to them.

## See also

- `../testing-and-ci/summary.md` — the two cop spec files
