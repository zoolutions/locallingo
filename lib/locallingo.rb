# frozen_string_literal: true

require_relative "locallingo/version"
require_relative "locallingo/settings"
require_relative "locallingo/configuration"
require_relative "locallingo/json_extraction"
require_relative "locallingo/key_flattener"
require_relative "locallingo/state_store"
require_relative "locallingo/providers/ruby_llm"
require_relative "locallingo/batch_translator"
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

  # Code-level settings (provider credentials) — see Locallingo::Settings.
  def self.settings
    @settings ||= Settings.new
  end

  # Configure the gem from Ruby — the credentials path for apps whose keys
  # don't live in ENV (call it from a Rails initializer or a `.locallingo.rb`
  # setup file next to `.locallingo.yml`; the CLI loads the latter on start).
  def self.configure
    yield settings
    settings
  end

  def self.reset_settings!
    @settings = nil
  end
end
