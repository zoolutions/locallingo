# frozen_string_literal: true

# Loaded only by the opt-in ActiveRecord specs: an in-memory SQLite database
# with JSON columns standing in for jsonb.
require "spec_helper"
require "active_record"
require "locallingo/active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table :articles, force: true do |t|
    t.json :body
    t.json :translation_state
    t.string :written_in, default: "en"
  end
end

class Article < ActiveRecord::Base
  include Locallingo::Translatable

  translates_content :body,
                     state: :translation_state,
                     source_locale: -> { written_in },
                     target_locales: %w[de sv]
end

RSpec.configure do |config|
  config.before(:each, :active_record) { Article.delete_all }
end
