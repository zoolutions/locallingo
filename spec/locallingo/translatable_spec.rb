# frozen_string_literal: true

require "active_record_helper"
require "open3"

RSpec.describe Locallingo::Translatable, :active_record do
  let(:drift) { Locallingo::Drift.new }
  let(:source) { { "title" => "Hello", "steps" => ["One", { "text" => "Two" }] } }
  let(:german) { { "title" => "Hallo", "steps" => ["Eins", { "text" => "Zwei" }] } }

  def translated_article(**attributes)
    article = Article.create!(body: { "en" => source, "de" => german }, **attributes)
    article.record_translation(:de)
    article.save!
    article
  end

  it "is not loaded by require \"locallingo\"" do
    script = 'require "locallingo"; exit(defined?(ActiveRecord) || defined?(ActiveSupport) ? 1 : 0)'
    _out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script, chdir: File.expand_path("../..", __dir__))

    expect(status).to be_success
  end

  describe "#translation_status" do
    it "is :missing for a locale with no content" do
      expect(Article.create!(body: { "en" => source }).translation_status(:de)).to eq(:missing)
    end

    it "is :current once a translation is recorded" do
      expect(translated_article.translation_status(:de)).to eq(:current)
    end

    it "is :outdated after the source changes" do
      article = translated_article
      article.update!(body: article.body.merge("en" => source.merge("title" => "Hello!")))

      expect(article.translation_status(:de)).to eq(:outdated)
    end

    it "is :current for an untracked translation" do
      article = Article.create!(body: { "en" => source })
      article.update_columns(body: article.body.merge("sv" => { "title" => "Hej" }))

      expect(article.translation_state).to be_nil
      expect(article.translation_status("sv")).to eq(:current)
    end

    it "reads the source locale from a callable evaluated on the record" do
      article = Article.create!(written_in: "sv", body: { "sv" => { "title" => "Hej" } })

      expect(article.translation_source_locale).to eq("sv")
      expect(article.translation_source).to eq("title" => "Hej")
      expect(article.translation_target_locales).to eq(%w[de sv])
    end
  end

  describe "#record_translation" do
    it "stores the Drift entry for the current source and target" do
      article = translated_article

      expect(article.reload.translation_state["de"]).to eq(drift.record(source:, target: german))
    end

    it "flags a manual entry" do
      article = Article.create!(body: { "en" => source, "de" => german })
      article.record_translation("de", manual: true)

      expect(article.translation_manual?(:de)).to be(true)
    end
  end

  it "records state with a custom hasher" do
    klass = Class.new(Article) do
      def self.name = "HashedArticle"

      translates_content :body, state: :translation_state, source_locale: "en", target_locales: %w[de],
                                hasher: ->(text) { "len:#{text.length}" }
    end
    article = klass.create!(body: { "en" => { "title" => "Hello" }, "de" => { "title" => "Hallo" } })
    article.record_translation(:de)

    expect(article.translation_state["de"]["source_hash"]).to eq("len:#{'{"title":"Hello"}'.length}")
  end

  describe "#translation_due?" do
    it "is true for a missing locale and false once translated" do
      expect(Article.create!(body: { "en" => source }).translation_due?(:de)).to be(true)
      expect(translated_article.translation_due?(:de)).to be(false)
      expect(translated_article.translation_due?(:de, force: true)).to be(true)
    end

    it "is false for a manual locale unless include_manual" do
      article = translated_article
      article.update!(body: article.body.merge("de" => german.merge("title" => "Servus")))

      expect(article.translation_due?(:de, force: true)).to be(false)
      expect(article.translation_due?(:de, force: true, include_manual: true)).to be(true)
    end
  end

  describe "#mark_hand_edits (before save)" do
    it "flags a hand-edited target locale as manual and re-baselines its target hash" do
      article = translated_article
      edited = german.merge("title" => "Servus")
      article.update!(body: article.body.merge("de" => edited))

      entry = article.reload.translation_state["de"]
      expect(entry).to eq(drift.record(source:, target: edited, manual: true))
      expect(article.translation_manual?(:de)).to be(true)
    end

    it "leaves untouched locales and source-only edits alone" do
      article = translated_article
      article.update!(body: article.body.merge("en" => source.merge("title" => "Hello!")))

      expect(article.translation_manual?(:de)).to be(false)
    end

    it "does not flag a cleared target (it becomes missing and due again)" do
      article = translated_article
      article.update!(body: article.body.except("de"))

      expect(article.translation_manual?(:de)).to be(false)
      expect(article.translation_status(:de)).to eq(:missing)
    end

    it "never flags the record's own source locale" do
      article = Article.create!(written_in: "sv", body: { "sv" => { "title" => "Hej" } })
      article.update!(body: { "sv" => { "title" => "Hej då" } })

      expect(article.translation_state).to be_nil
    end

    it "flags an untracked locale a person wrote in this save" do
      article = Article.create!(body: { "en" => source })
      article.update!(body: article.body.merge("sv" => { "title" => "Hej" }))

      expect(article.translation_manual?(:sv)).to be(true)
    end
  end

  describe "#translation_segments" do
    it "includes strings inside nested arrays, with KeyFlattener-style paths" do
      article = Article.create!(body: { "en" => { "table" => [%w[Name Price], ["A", 1]], "t" => { "x" => "y" } } })

      expect(article.translation_segments)
        .to eq("table[0][0]" => "Name", "table[0][1]" => "Price", "table[1][0]" => "A", "t.x" => "y")
    end
  end

  describe "#build_translation_target" do
    it "sets strings inside nested arrays" do
      article = Article.create!(body: { "en" => { "table" => [%w[Name Price], ["A", 1]] } })

      target = article.build_translation_target("table[0][0]" => "Name_DE", "table[0][1]" => "Preis",
                                                "table[1][0]" => "A_DE")

      expect(target).to eq("table" => [%w[Name_DE Preis], ["A_DE", 1]])
    end

    it "sets translated leaves into a copy of the source, keeping every other value and container" do
      body = source.merge("count" => 3, "ids" => [12, 13], "table" => [%w[Name Price]], "tags" => [], "meta" => {})
      article = Article.create!(body: { "en" => body })

      target = article.build_translation_target("title" => "Hallo", "steps[0]" => "Eins", "steps[1].text" => "Zwei")

      expect(target).to eq(body.merge("title" => "Hallo", "steps" => ["Eins", { "text" => "Zwei" }]))
      expect(article.translation_source).to eq(body)
    end
  end
end
