# frozen_string_literal: true

# The lingo CLI: subcommands, shared options, and the legacy flag aliases.
class Views::Docs::Pages::Cli < DocsUI::Page
  title "CLI reference"
  eyebrow "CLI"

  def lead = "The lingo command — subcommands, shared options, and exit codes."

  def content
    shape
    shared_options
    legacy_flags
    exit_codes
  end

  private

  def shape
    DocsUI::Section("Shape", description: "lingo <command> [options]") do
      md <<~'MD'
        The canonical form is a subcommand followed by options. With no command,
        `lingo` prints `status`.
      MD
      DocsUI::Code(<<~'BASH', filename: "shell")
        lingo status                    # translation status per locale
        lingo translate --locale de     # translate missing / changed keys
        lingo validate --strict         # CI gate (exit 1 on strict-tier issues)
        lingo quality --ai              # quality linting + optional AI pass
        lingo fix-quality --locale en   # auto-fix the fixable issues
        lingo accept-edits --locale de  # mark current translations as intentional
        lingo sync                      # rebuild drift state from current files
        lingo hash                      # source-translation fingerprint
      BASH
      md <<~'MD'
        Each command is described in detail on the [Commands](/docs/commands)
        page.
      MD
    end
  end

  def shared_options
    DocsUI::Section("Shared options") do
      md <<~'MD'
        | Option | Meaning |
        | --- | --- |
        | `-l`, `--locale LOCALE` | Restrict to a single target locale |
        | `-f`, `--force` | Re-translate all keys (not just missing/changed) |
        | `--force-key KEY` | Re-translate one specific key (repeatable); skips `manual` keys |
        | `--include-manual` | Let `--force-key` overwrite `manual` keys |
        | `--key KEY` | `accept-edits`, `quality`: act on one specific key (repeatable) |
        | `--prefix PREFIX` | `quality`: check only keys starting with `PREFIX` |
        | `-v`, `--verbose` | Verbose logging |
        | `-n`, `--dry-run` | Show what would happen without writing files |
        | `--strict` | Fail on the strict-tier violation types |
        | `--strict-all` | Fail on the strict-all-tier violation types |
        | `--ai` | Use the AI pass for quality suggestions |
        | `--json` | Emit machine-readable JSON |
        | `--package PATH` | Scope to a package from `.locallingo.yml` |
        | `-h`, `--help` | Show help |
      MD
    end
  end

  def legacy_flags
    DocsUI::Section("Legacy flag aliases") do
      md <<~'MD'
        If you're migrating from a `bin/translate` script, the old `--flag`
        command forms still work — they print a one-line deprecation notice and
        map onto the new subcommands, so you can move CI and docs over
        incrementally.
      MD
      DocsUI::Code(<<~'TEXT', filename: "deprecated → canonical")
        --status       → status
        --translate    → translate
        --validate     → validate
        --check-quality → quality
        --fix-quality  → fix-quality
        --sync-state   → sync
      TEXT
    end
  end

  def exit_codes
    DocsUI::Section("Exit codes") do
      md <<~'MD'
        `validate` sets a failing exit code only under `--strict` /
        `--strict-all`. It returns `1` when any violation whose type is listed in
        the matching `strict` tier is present, and `0` otherwise — so it slots
        straight into a CI step.

        `translate` returns `1` when any key could not be translated: it prints
        `⚠️ Translation finished: N keys failed` and lists them. Outside
        `--dry-run`, the keys that were translated are still written and the
        `after_translate` hooks still run. Under `--dry-run` nothing is written,
        no hooks run, and failures are reported with exit code `0`.
        Appending `|| true` restores the old always-`0` behaviour, but it also
        hides every other failure, such as missing credentials or a broken
        `.locallingo.yml`.
      MD
    end
  end
end
