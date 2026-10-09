# frozen_string_literal: true

require "optparse"

require_relative "configuration"
require_relative "manager"
require_relative "quality_checker"
require_relative "reporter"

module Locallingo
  # The `lingo` command-line interface.
  #
  # Canonical form is subcommands (`lingo translate`, `lingo validate`, ...).
  # The legacy flag form (`lingo --translate`) still works but prints a
  # deprecation notice, so callers can migrate incrementally.
  class CLI
    CLI_NAME = "lingo"

    # Optional Ruby setup file loaded before dispatch — the hook for apps to
    # configure credentials (via Locallingo.configure or RubyLLM.configure)
    # without booting Rails.
    SETUP_FILENAME = ".locallingo.rb"

    # subcommand => the legacy flag it replaces
    COMMANDS = {
      "status" => "--status",
      "translate" => "--translate",
      "validate" => "--validate",
      "quality" => "--check-quality",
      "fix-quality" => "--fix-quality",
      "accept-edits" => "--accept-edits",
      "hash" => "--hash",
      "sync" => "--sync-state"
    }.freeze

    # legacy flag => subcommand (for the deprecation path)
    LEGACY_FLAGS = {
      "--status" => "status",
      "--translate" => "translate",
      "--validate" => "validate",
      "--check-quality" => "quality",
      "--fix-quality" => "fix-quality",
      "--accept-edits" => "accept-edits",
      "--hash" => "hash",
      "--sync-state" => "sync"
    }.freeze

    def self.start(argv = ARGV)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @options = { format: :text }
    end

    def run
      command = resolve_command
      options = parse_options!
      load_setup_file
      config = Locallingo.configuration(root_path: Dir.pwd, package: options[:package])
      dispatch(command, config, options)
    rescue Locallingo::Error => e
      warn "❌ #{e.message}"
      exit 1
    end

    private

    # An absent file is fine; errors in the file propagate loudly. `load` (not
    # require) so repeated in-process invocations re-execute it.
    def load_setup_file
      path = File.join(Dir.pwd, SETUP_FILENAME)
      load path if File.file?(path)
    end

    # Determine the subcommand, translating a leading legacy flag (with a
    # deprecation notice) and defaulting to `status`.
    def resolve_command
      first = @argv.first
      return "status" if first.nil?

      if LEGACY_FLAGS.key?(first)
        @argv.shift
        subcommand = LEGACY_FLAGS[first]
        warn "[deprecated] `#{first}` — use `#{CLI_NAME} #{subcommand}` instead."
        return subcommand
      end

      # A leading non-flag token is the subcommand.
      return @argv.shift unless first.start_with?("-")

      "status"
    end

    def parse_options!
      parser = build_parser
      parser.parse!(@argv)
      @options
    end

    def build_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: #{CLI_NAME} <command> [options]\n\nCommands:\n  " \
                      "#{COMMANDS.keys.join(", ")}\n\nOptions:"

        opts.on("-l", "--locale LOCALE", "Process specific locale") { |v| @options[:locale] = v }
        opts.on("-f", "--force", "Force re-translation of all keys") { @options[:force] = true }
        opts.on("--force-key KEY", "Force re-translation of a specific key") do |v|
          (@options[:force_keys] ||= []) << v
        end
        opts.on("--key KEY", "accept-edits, quality: act on a specific key (repeatable)") do |v|
          (@options[:keys] ||= []) << v
        end
        opts.on("--all", "accept-edits: mark every translated key as manual") { @options[:all] = true }
        opts.on("-v", "--verbose", "Verbose output") { @options[:verbose] = true }
        opts.on("-n", "--dry-run", "Show what would be done without changing files") { @options[:dry_run] = true }
        opts.on("--strict", "Fail on strict-tier issues (for CI)") { @options[:strict] = true }
        opts.on("--strict-all", "Fail on strict-all-tier issues (for full CI)") do
          @options[:strict] = true
          @options[:strict_all] = true
        end
        quality_options(opts)
        opts.on("--json", "Output in JSON format") { @options[:format] = :json }
        opts.on("--package PATH", "Scope to a package from .locallingo.yml") { |v| @options[:package] = v }
        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit 0
        end
      end
    end

    def quality_options(opts)
      opts.on("--ai", "Use AI for quality suggestions") { @options[:use_ai] = true }
      opts.on("--prefix PREFIX", "quality: check only keys starting with PREFIX (e.g. yoga.)") do |v|
        @options[:prefix] = v
      end
    end

    def dispatch(command, config, options)
      reporter = Reporter.new(config:, format: options[:format], cli_name: CLI_NAME)

      case command
      when "status" then cmd_status(config, options, reporter)
      when "translate" then cmd_translate(config, options)
      when "validate" then cmd_validate(config, options, reporter)
      when "quality" then cmd_quality(config, options, reporter)
      when "fix-quality" then cmd_fix_quality(config, options)
      when "accept-edits" then cmd_accept_edits(config, options)
      when "hash" then cmd_hash(config, options)
      when "sync" then cmd_sync(config, options)
      else
        warn "Unknown command: #{command}\nRun `#{CLI_NAME} --help`."
        exit 1
      end
    end

    def cmd_status(config, options, reporter)
      reporter.status(manager(config, options).status)
    end

    def cmd_translate(config, options)
      mgr = manager(config, options)
      puts "🔄 Translating..." if options[:verbose]
      failed = mgr.translate!(locale: options[:locale], force: options[:force],
                              force_keys: options[:force_keys] || [])
      unless options[:dry_run]
        puts "📝 Running post-translate hooks..."
        mgr.run_after_translate_hooks
      end
      report_translated(failed, dry_run: options[:dry_run])
    end

    # Hooks have already run for the keys that were written; a failed key still
    # fails the run (outside --dry-run) so CI does not ship missing translations.
    def report_translated(failed, dry_run:)
      count = failed.values.sum(&:size)
      if count.zero?
        puts "✅ Translation complete!"
      else
        puts "⚠️ Translation finished: #{count} #{count == 1 ? "key" : "keys"} failed " \
             "(re-run with -v for details)"
        failed.each { |locale, keys| keys.each { |key| puts "  - #{locale}: #{key}" } }
      end
      puts "(dry run - no changes made)" if dry_run
      exit 1 if count.positive? && !dry_run
    end

    def cmd_validate(config, options, reporter)
      violations = manager(config, options).validate
      exit(reporter.violations(violations, strict: options[:strict], strict_all: options[:strict_all]))
    end

    def cmd_quality(config, options, reporter)
      locale = options[:locale] || config.source_locale
      raise Error, "--key and --prefix cannot be combined" if options[:keys] && options[:prefix]

      suggestions = quality_checker(config, options).check(
        locale:, use_ai: options[:use_ai], prefix: options[:prefix], keys: options[:keys]
      )
      reporter.quality(suggestions, locale:)
    end

    def cmd_fix_quality(config, options)
      locale = options[:locale] || config.source_locale
      puts(options[:dry_run] ? "🔍 Checking fixes for #{locale}..." : "🔧 Fixing quality issues for #{locale}...")
      result = quality_checker(config, options).fix!(locale:, dry_run: options[:dry_run])
      puts "\nFixed: #{result[:fixed]} files"
      puts "Skipped: #{result[:skipped]} non-fixable suggestions"
      puts "(dry run - no changes made)" if options[:dry_run]
    end

    def cmd_accept_edits(config, options)
      unless config.validator_enabled?(:manual_edits)
        warn "manual_edits validator is disabled in .locallingo.yml — nothing to accept."
        return
      end

      results = manager(config, options).accept_edits!(
        locale: options[:locale], keys: options[:keys] || [], all: options.fetch(:all, false)
      )
      report_accepted(results)
      puts "(dry run - no changes made)" if options[:dry_run]
    end

    def report_accepted(results)
      total = results.values.sum(&:size)
      if total.zero?
        puts "Nothing to accept — no hand-edited translations found."
        return
      end

      results.each { |locale, keys| puts "  #{locale}: #{keys.size} key(s)" if keys.any? }
      puts "✅ Marked #{total} translation(s) as intentional."
    end

    def cmd_hash(config, options)
      hash = manager(config, options).source_hash
      options[:format] == :json ? puts(JSON.generate({ hash: })) : puts(hash)
    end

    def cmd_sync(config, options)
      mgr = manager(config, options)
      puts(options[:dry_run] ? "🔍 Would sync state file..." : "🔄 Syncing state file with current translations...")
      state = mgr.sync_state!
      total = state.values.sum { |locale_state| locale_state.keys.size }
      puts "\nState directory: #{config.state_dir}"
      state.each { |locale, locale_state| puts "  #{locale}: #{locale_state.keys.size} keys" }
      puts "Total tracked keys: #{total}"
      puts "(dry run - no changes made)" if options[:dry_run]
    end

    def manager(config, options)
      Manager.new(config:, dry_run: options[:dry_run], verbose: options[:verbose], cli_name: CLI_NAME)
    end

    def quality_checker(config, options)
      QualityChecker.new(config:, verbose: options[:verbose])
    end
  end
end
