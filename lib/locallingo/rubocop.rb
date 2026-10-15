# frozen_string_literal: true

# Loads Locallingo's RuboCop cops. `require`d only from a host app's
# `.rubocop.yml` (`require: locallingo/rubocop`), so `rubocop` is never pulled
# into the app's runtime — it is a development-time dependency of both the host
# app and this gem.
#
# The shipped defaults live in config/default.yml; a host app enables/scopes the
# cops there via `inherit_gem`.

require "rubocop"

require_relative "../rubocop/cop/locallingo/relative_i18n_key"
require_relative "../rubocop/cop/locallingo/strftime_in_view"

module Locallingo
  # Absolute path to the cop defaults, for `inherit_gem: locallingo: <path>`.
  module RuboCop
    CONFIG_DEFAULT = File.expand_path("../../config/default.yml", __dir__).freeze
  end
end
