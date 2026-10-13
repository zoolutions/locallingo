# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  # Only for the opt-in `locallingo/active_record` concern's specs (in-memory SQLite).
  gem "activerecord", ">= 7.1"
  # ruby_llm allows faraday >= 1.10, and faraday-net_http 3.5.0 (which only
  # supports newer faraday) made Bundler resolve faraday 2.0.0, which never
  # registers the :net_http adapter. Keep the resolver on a current faraday.
  gem "faraday", ">= 2.14.4"
  gem "rake"
  gem "rspec"
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rake", require: false
  gem "rubocop-rspec", require: false
  gem "simplecov", require: false
  gem "sqlite3", ">= 2.1"
end
