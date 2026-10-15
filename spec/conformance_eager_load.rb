# frozen_string_literal: true

# conformance-kit's audit.require: loads every file under lib/, including the
# opt-in ones `require "locallingo"` leaves out (locallingo/active_record needs
# ActiveSupport, locallingo/rubocop needs RuboCop; the dev bundle has both), so
# `conformance-audit --strict` sees the whole gem.
require_relative "../lib/locallingo"
Dir[File.expand_path("../lib/**/*.rb", __dir__)].each { |file| require file }
