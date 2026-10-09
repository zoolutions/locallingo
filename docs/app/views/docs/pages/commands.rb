# frozen_string_literal: true

# Each lingo subcommand, what it does, and when to reach for it.
class Views::Docs::Pages::Commands < DocsUI::Page
  title "Commands"
  eyebrow "CLI"

  def lead = "What each lingo subcommand does."

  def content
    status
    translate
    validate
    quality_cmds
    accept_edits
    sync
    hash_cmd
  end

  private

  def status
    DocsUI::Section("status") do
      md <<~'MD'
        Prints, for each target locale, the total key count and how many are
        translated, missing, or outdated. No credentials, no writes — the
        read-only snapshot. Add `--json` for a machine-readable form.
      MD
    end
  end

  def translate
    DocsUI::Section("translate") do
      md <<~'MD'
        Translates the missing and outdated keys for one or all target locales and
        merges the results into `config/locales/`. Determines the work from the
        source-hash state, so unchanged keys are never re-sent.

        - `--locale de` limits to one locale.
        - `--force` re-translates everything (respecting protected manual edits).
        - `--force-key a.b.c` re-translates specific keys. Manual-flagged keys
          are skipped and named on stderr; add `--include-manual` to overwrite
          them (their `manual` flag survives the rewrite).
        - `--dry-run` shows the plan without writing.

        On success it runs the configured `after_translate` hooks. Requires
        provider credentials.
      MD
    end
  end

  def validate
    DocsUI::Section("validate") do
      md <<~'MD'
        Runs the configured validators and prints the violations. `--strict` and
        `--strict-all` make it exit non-zero on their respective violation types —
        this is the CI command. See [Validators](/docs/validators) for the
        checks and [Continuous integration](/docs/ci) for wiring.
      MD
    end
  end

  def quality_cmds
    DocsUI::Section("quality / fix-quality") do
      md <<~'MD'
        `quality` lints a locale's text (defaults to the source locale) with the
        static rules, terminology list, and — with `--ai` — an LLM review pass.
        `--prefix yoga.` scopes it to one namespace; `--key a.b.c` (repeatable)
        to exact keys.
        `fix-quality` rewrites the auto-fixable suggestions (universal fixes and
        British spellings) back into the locale files, preserving case; add
        `--dry-run` to preview. See [Quality linting](/docs/quality).
      MD
    end
  end

  def accept_edits
    DocsUI::Section("accept-edits") do
      md <<~'MD'
        When the `manual_edits` validator is enabled, `accept-edits` records
        hand-edited target values as intentional so they are protected from being
        overwritten by the next `translate` and no longer flagged as hand-edited.

        - Unscoped, it accepts exactly the keys the `manual_edits` validator
          flags — nothing else changes.
        - `--key a.b.c` (repeatable) accepts specific keys, drifted or not.
        - `--all` marks every translated key as manual — the blanket form, for
          adopting locallingo on an app whose translations were all hand-made.
        - `--locale de` limits any of the above to one locale.

        See [Drift & state](/docs/drift-state).
      MD
    end
  end

  def sync
    DocsUI::Section("sync") do
      md <<~'MD'
        Refreshes the `.i18n-state/` drift state from the current locale files —
        for initial setup on an existing app, or after editing source strings, so
        `validate` doesn't report spurious "outdated" keys. It updates each key's
        `source_hash`, backfills a `target_hash` baseline for entries that lack
        one (hand-added translations), and prunes entries whose keys were
        removed. An existing `target_hash` and all `manual` flags are always
        preserved, so hand-edit protection never depends on when sync last ran.
      MD
    end
  end

  def hash_cmd
    DocsUI::Section("hash") do
      md <<~'MD'
        Prints a single CRC32 fingerprint of the current source translations —
        handy as a cache key (e.g. to skip a translate step in CI when the source
        hasn't changed). `--json` wraps it in an object.
      MD
    end
  end
end
