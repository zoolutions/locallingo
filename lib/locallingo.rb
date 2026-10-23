# frozen_string_literal: true

require "monitor"
require_relative "locallingo/version"
require_relative "locallingo/settings"
require_relative "locallingo/configuration"
require_relative "locallingo/json_extraction"
require_relative "locallingo/key_flattener"
require_relative "locallingo/state_store"
require_relative "locallingo/drift"
require_relative "locallingo/providers/ruby_llm"
require_relative "locallingo/placeholders"
require_relative "locallingo/batch_translator"
require_relative "locallingo/prompt"
require_relative "locallingo/translator"
require_relative "locallingo/record_translator"
require_relative "locallingo/validators/missing"
require_relative "locallingo/validators/outdated"
require_relative "locallingo/validators/duplicate_values"
require_relative "locallingo/validators/manual_edits"
require_relative "locallingo/quality/static_rules"
require_relative "locallingo/quality/british_spellings"
require_relative "locallingo/quality/terminology"
require_relative "locallingo/manager"
require_relative "locallingo/quality_checker"
require_relative "locallingo/reporter"
require_relative "locallingo/cli"

# Locallingo — AI-assisted i18n translation, drift detection and quality linting.
#
# The public entry points are the `lingo` CLI (exe/lingo → Locallingo::CLI) and,
# programmatically, Locallingo::Manager / Locallingo::QualityChecker, both driven
# by a Locallingo::Configuration loaded from `.locallingo.yml`.
module Locallingo
  class Error < StandardError; end

  # Raised when an LLM call is attempted but the configured provider has no
  # credentials available.
  class MissingCredentialsError < Error; end

  # Load the configuration for +root_path+ (defaults to the current directory),
  # optionally scoped to a package path from the `packages:` list.
  def self.configuration(root_path: Dir.pwd, package: nil)
    Configuration.load(root_path:, package:)
  end

  # Boot-time state, finalized: always a frozen Settings, so any thread or
  # Ractor reads finished settings and only `configure` replaces them. With
  # String keys (or none) it is Ractor-shareable; a callable key is not, so it
  # keeps the settings readable on the main Ractor only.
  #
  # rubocop:disable ThreadSafety/ClassInstanceVariable -- @settings is written only by configure and reset_settings!, at boot on the main Ractor, and always holds a frozen Settings; @configure_lock (engines without Ractor only) is set once, at load
  @settings = Settings.new.freeze

  # Serializes configure: one Monitor per Ractor, in Ractor-local storage (only
  # the main Ractor can publish @settings, so in practice the main Ractor's).
  # The main Ractor's is made here, at load, never lazily. A Monitor, so a
  # configure nested in a configure block does not deadlock. Engines without
  # Ractor keep it in @configure_lock.
  if defined?(::Ractor)
    ::Ractor.current[:locallingo_configure_lock] = Monitor.new
  else
    @configure_lock = Monitor.new
  end

  # Code-level settings (provider credentials) — see Locallingo::Settings.
  def self.settings = @settings

  # Configure the gem from Ruby — the credentials path for apps whose keys
  # don't live in ENV (call it from a Rails initializer or a `.locallingo.rb`
  # setup file next to `.locallingo.yml`; the CLI loads the latter on start).
  # Yields a copy of the current settings, then publishes it frozen in one
  # assignment: a concurrent reader sees the old settings or the new, never
  # half of them. Concurrent calls run one at a time, so neither drops the
  # other's keys. Calling it again keeps the keys it does not set.
  def self.configure
    configure_lock.synchronize do
      draft = settings.dup
      yield draft
      @settings = draft.freeze
    end
  end

  # Back to frozen, blank defaults (for tests).
  def self.reset_settings!
    @settings = Settings.new.freeze
  end

  # Another Ractor's lock is made on first use: atomically on Ruby 3.4+; below,
  # two of its threads could each make one, which is harmless because a
  # non-main Ractor cannot publish settings anyway.
  def self.configure_lock
    return @configure_lock unless defined?(::Ractor)

    key = :locallingo_configure_lock
    return ::Ractor.store_if_absent(key) { Monitor.new } if ::Ractor.respond_to?(:store_if_absent)

    ::Ractor.current[key] ||= Monitor.new
  end
  private_class_method :configure_lock
  # rubocop:enable ThreadSafety/ClassInstanceVariable
end
