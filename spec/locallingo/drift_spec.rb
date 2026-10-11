# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::Drift do
  subject(:drift) { described_class.new }

  let(:hash) { Locallingo::StateStore.method(:hash) }
  let(:entry) { drift.record(source: "Hello", target: "Hallo") }

  describe "#digest" do
    it "hashes a String raw, exactly like StateStore (existing state files stay current)" do
      expect(drift.digest("Hello")).to eq(Locallingo::StateStore.hash("Hello"))
    end

    it "hashes nested values over canonical JSON, independent of key order" do
      a = { "title" => "Hi", "body" => { "x" => "1", "y" => ["a", { "q" => "r", "p" => "s" }] } }
      b = { "body" => { "y" => ["a", { "p" => "s", "q" => "r" }], "x" => "1" }, "title" => "Hi" }

      expect(drift.digest(a)).to eq(drift.digest(b))
      expect(drift.digest(a)).not_to eq(drift.digest(a.merge("title" => "Ho")))
    end

    it "keeps array order significant" do
      expect(drift.digest(%w[a b])).not_to eq(drift.digest(%w[b a]))
    end

    it "uses a custom hasher" do
      sha = described_class.new(hasher: ->(text) { "sha:#{text.length}" })

      expect(sha.digest("Hello")).to eq("sha:5")
      expect(sha.record(source: "Hello", target: "Hallo")).to eq("source_hash" => "sha:5", "target_hash" => "sha:5")
    end
  end

  describe "#record" do
    it "builds the StateStore entry shape" do
      expect(entry).to eq("source_hash" => hash.call("Hello"), "target_hash" => hash.call("Hallo"))
    end

    it "flags a manual entry" do
      expect(drift.record(source: "Hello", target: "Hallo", manual: true)).to include("manual" => true)
    end
  end

  describe "#status" do
    it "is :missing for an absent or blank target" do
      [nil, "", "  ", {}, { "a" => " " }, { "a" => ["", nil] }].each do |target|
        expect(drift.status(source: "Hello", target:, entry:)).to eq(:missing), target.inspect
      end
    end

    it "is :outdated when the source changed since the entry was recorded" do
      expect(drift.status(source: "Hello!", target: "Hallo", entry:)).to eq(:outdated)
    end

    it "is :current when the source is unchanged" do
      expect(drift.status(source: "Hello", target: "Hallo", entry:)).to eq(:current)
    end

    it "is :current for an untracked target (no entry or no source_hash)" do
      expect(drift.status(source: "Hello", target: "Hallo", entry: nil)).to eq(:current)
      expect(drift.status(source: "Hello", target: "Hallo", entry: { "target_hash" => "x" })).to eq(:current)
    end

    it "ignores the manual flag (it reports, due? decides)" do
      manual = drift.record(source: "Hello", target: "Hallo", manual: true)

      expect(drift.status(source: "Hello!", target: "Hallo", entry: manual)).to eq(:outdated)
    end

    it "works on nested values" do
      source = { "title" => "Hello", "tags" => %w[a b] }
      recorded = drift.record(source:, target: { "title" => "Hallo" })

      expect(drift.status(source: source.merge("tags" => %w[b a]), target: { "title" => "Hallo" }, entry: recorded))
        .to eq(:outdated)
    end
  end

  describe "#manual?" do
    it { expect(drift.manual?(entry)).to be(false) }
    it { expect(drift.manual?(entry.merge("manual" => true))).to be(true) }
    it { expect(drift.manual?(nil)).to be(false) }
    it { expect(drift.manual?("garbage")).to be(false) }
  end

  describe "#hand_edited?" do
    it "is true when the target changed since it was recorded" do
      expect(drift.hand_edited?(target: "Hallo!", entry:)).to be(true)
    end

    it "is false for an unchanged target" do
      expect(drift.hand_edited?(target: "Hallo", entry:)).to be(false)
    end

    it "is false once the entry is flagged manual" do
      expect(drift.hand_edited?(target: "Hallo!", entry: entry.merge("manual" => true))).to be(false)
    end

    it "is false without a recorded target_hash" do
      expect(drift.hand_edited?(target: "Hallo!", entry: { "source_hash" => "x" })).to be(false)
      expect(drift.hand_edited?(target: "Hallo!", entry: nil)).to be(false)
    end
  end

  describe "#due?" do
    let(:manual) { entry.merge("manual" => true) }

    it "is true for a missing target" do
      expect(drift.due?(source: "Hello", target: nil, entry: nil)).to be(true)
    end

    it "is true for an outdated, non-manual target" do
      expect(drift.due?(source: "Hello!", target: "Hallo", entry:)).to be(true)
    end

    it "is false for a current target unless forced" do
      expect(drift.due?(source: "Hello", target: "Hallo", entry:)).to be(false)
      expect(drift.due?(source: "Hello", target: "Hallo", entry:, force: true)).to be(true)
    end

    it "never retranslates a manual target, even forced or missing" do
      expect(drift.due?(source: "Hello!", target: "Hallo", entry: manual)).to be(false)
      expect(drift.due?(source: "Hello", target: "Hallo", entry: manual, force: true)).to be(false)
      expect(drift.due?(source: "Hello", target: "", entry: manual)).to be(false)
    end

    it "lets include_manual retranslate a due or forced manual target" do
      expect(drift.due?(source: "Hello!", target: "Hallo", entry: manual, include_manual: true)).to be(true)
      expect(drift.due?(source: "Hello", target: "Hallo", entry: manual, force: true, include_manual: true)).to be(true)
      expect(drift.due?(source: "Hello", target: "Hallo", entry: manual, include_manual: true)).to be(false)
    end

    it "is false when there is no source text" do
      expect(drift.due?(source: " ", target: nil, entry: nil, force: true)).to be(false)
    end
  end
end
