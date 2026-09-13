# Docs site (`docs/`)

A self-contained Rails 8.1 app built on [docs-kit](https://github.com/zoolutions/docs-kit),
with its own `Gemfile`, `.rubocop.yml`, `bun.lock` and Dockerfile. It is not part
of the gem (the gemspec ships only `exe/`, `lib/`, `config/`, `CHANGELOG.md`,
`LICENSE.txt`, `README.md`) and it has no PR CI.

## 1. How a page exists

Every page is a `DocsUI::Page` subclass under `docs/app/views/docs/pages/` **and**
a `page "Title", group: …` line in `docs/app/models/doc.rb`. Without the registry
line the page is not routed and not in the nav; the generator
(`bin/rails g docs_kit:page "Title" --group=…`) writes both. A registered page
whose view class does not resolve is silently skipped everywhere, so the registry
doubles as a burn-down list.

The full authoring contract is `docs/AGENTS.md` (and, live, `/docs/authoring`).
Its load-bearing rules: prose is `md <<~'MD'` inside a `DocsUI::Section`, never a
Markdown `##` for page structure; reference material uses
`DocsUI::PropTable`/`FieldTable`/`Callout`/`Code`; the page must render with
JavaScript off; never hand-write HTML or daisyUI markup.

## 2. The 16 pages and what each documents

| Page (slug) | Documents |
|---|---|
| Overview (`overview`) | what the gem is, how the parts fit |
| Installation (`installation`) | Gemfile, binstub, credentials, config file |
| Quick start (`quick-start`) | status → translate → validate → sync |
| CLI reference (`cli`) | command shape, shared options, legacy aliases, exit codes |
| Commands (`commands`) | each subcommand in `CLI::COMMANDS` |
| Configuration (`configuration`) | `.locallingo.yml`, merge order, ERB |
| Providers & models (`providers`) | `provider:`, the two models, credentials |
| Prompt & glossary (`prompt-glossary`) | `context`, `glossary`, `placeholder_style`, language guides |
| Multiple packages (`packages`) | the `packages:` list and `--package` |
| Configuration reference (`configuration-reference`) | every config key with its default |
| Validators (`validators`) | the four validators and their violation types |
| Drift & state (`drift-state`) | hashes, `.i18n-state/`, manual protection, `sync` |
| Quality linting (`quality`) | static rules, terminology, British spellings, AI pass, fixing |
| RuboCop cops (`rubocop-cops`) | the two cops and their config |
| Continuous integration (`ci`) | wiring `validate --strict` into a pipeline |
| Migrating from a script (`migrating`) | `bin/translate` → `lingo`, flag→subcommand |

Which page a behaviour change must update follows that table: a new CLI option
touches `cli` *and* `commands`; a new config key touches `configuration` *and*
`configuration-reference`; a change to what `sync` preserves touches
`drift-state` *and* `commands`. A fact that appears on two pages has to change on
both.

## 3. Tooling

- `cd docs && bin/dev` — Procfile-driven local server.
- `cd docs && bin/rubocop` — omakase + docs-kit cops, `TargetRubyVersion: 3.4`,
  with an explicit `AllCops/Include` so the nested app lints itself.
- `cd docs && bin/ci` — the ActiveSupport::ContinuousIntegration script in
  `docs/config/ci.rb`: setup, `bin/rubocop`, `bin/bundler-audit`,
  `bin/importmap audit`, `bin/brakeman`. **No test step — the app has no
  `spec/` directory.**
- `cd docs && bun run build:css` → `bin/build-css`, which resolves the `daisyui`
  and `docs-kit` gem paths with `bundle show`, writes them into
  `app/assets/stylesheets/tailwind.sources.css`, and runs the Tailwind CLI. It
  aborts if a gem path cannot be resolved, because a silently-missing `@source`
  ships an unstyled site.

`docs/Gemfile` takes the gem with `gem "locallingo", path: "..", require:
"locallingo/version"` — only the version constant loads, so the gem's own
runtime deps never boot inside the docs app. `docs/Gemfile.lock` is **not**
committed (the root `.gitignore`'s bare `Gemfile.lock` matches it), so unlike
sibling repos there is no post-release lockfile pin to refresh.

`app/assets/stylesheets/tailwind.sources.css` is a committed generated file
holding absolute gem paths; see `../review/commands-and-docs.md` for why that is
deliberate. `app/assets/builds/*` is gitignored.

## 4. Deploy

`docs/config/deploy.yml` is a dash 4 config (`minimum_version: 4.0.7`) targeting
ghcr.io image `zoolutions/locallingo`, service `locallingo`, behind
dash-proxy with compression, a 300s shared cache, security headers and
`intercept_errors` for 502/503/504. It ships on every published GitHub release
via `deploy-docs.yml`, so the docs go live with the gem.

## See also

- `docs/AGENTS.md` — the authoring contract in full
- `../testing-and-ci/summary.md` — why no docs job runs on a PR
