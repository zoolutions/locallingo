# frozen_string_literal: true

require "active_record_helper"

RSpec.describe Locallingo::RecordTranslator, :active_record do
  let(:config) { Locallingo::Configuration.new(root_path: Dir.pwd) }
  let(:translator) { Locallingo::Translator.new(config:, pause: 0, logger: Logger.new(nil)) }
  let(:calls) { [] }
  let(:drift) { Locallingo::Drift.new }

  def stub_chat(&responder)
    stub_llm_chat do |payload:, **|
      calls << payload
      reply = payload.transform_values { |v| "DE:#{v}" }
      responder ? yield(payload, reply) : reply
    end
  end

  def article(body) = Article.create!(body: { "en" => body })

  it "translates every due record in one batched call and records the state" do
    stub_chat
    first = article("title" => "Hello", "steps" => ["One", { "text" => "Two", "n" => 2 }])
    second = article("title" => "Bye")

    result = described_class.new(translator:).call(Article.all, to: "de")

    expect(calls.size).to eq(1)
    expect(calls.first.keys).to contain_exactly(
      "#{first.id}.title", "#{first.id}.steps[0]", "#{first.id}.steps[1].text", "#{second.id}.title"
    )
    expect(result).to eq(translated: 2, failed: {}, skipped: [])
    expect(first.reload.body["de"])
      .to eq("title" => "DE:Hello", "steps" => ["DE:One", { "text" => "DE:Two", "n" => 2 }])
    expect(first.translation_status(:de)).to eq(:current)
    expect(first.translation_state["de"]).to eq(drift.record(source: first.body["en"], target: first.body["de"]))
  end

  it "passes style and instructions through to the prompt" do
    prompts = []
    stub_llm_chat do |payload:, instructions:, **|
      prompts << instructions
      payload.transform_values { |v| "DE:#{v}" }
    end
    article("title" => "Hello")

    described_class.new(translator:).call(Article.all, to: :de, style: :prose, instructions: "Warm voice.")

    expect(prompts).to eq([Locallingo::Prompt.translation(config:, from: "en", to: "de", style: :prose,
                                                          instructions: "Warm voice.")])
  end

  it "only sends records that are due" do
    stub_chat
    current = article("title" => "Hello")
    described_class.new(translator:).call(Article.all, to: "de")
    calls.clear
    fresh = article("title" => "New")

    result = described_class.new(translator:).call(Article.all, to: "de")

    expect(calls.map(&:keys)).to eq([["#{fresh.id}.title"]])
    expect(result[:translated]).to eq(1)
    expect(current.reload.body["de"]).to eq("title" => "DE:Hello")
  end

  it "retranslates current records with force, but never manual ones without include_manual" do
    stub_chat
    record = article("title" => "Hello")
    described_class.new(translator:).call(Article.all, to: "de")
    manual = article("title" => "Hand")
    manual.update!(body: manual.body.merge("de" => { "title" => "Hand-written" }))
    calls.clear

    described_class.new(translator:).call(Article.all, to: "de", force: true)

    expect(calls.map(&:keys)).to eq([["#{record.id}.title"]])
    expect(manual.reload.body["de"]).to eq("title" => "Hand-written")
  end

  it "keeps the manual flag when include_manual retranslates a manual record" do
    stub_chat
    manual = article("title" => "Hand")
    manual.update!(body: manual.body.merge("de" => { "title" => "Hand-written" }))

    described_class.new(translator:).call(Article.all, to: "de", force: true, include_manual: true)

    expect(manual.reload.body["de"]).to eq("title" => "DE:Hand")
    expect(manual.translation_manual?(:de)).to be(true)
  end

  it "skips a record whose source changed while the model answered" do
    record = article("title" => "Hello")
    stub_chat do |_payload, reply|
      Article.find(record.id).update_columns(body: { "en" => { "title" => "Hello again" } })
      reply
    end

    result = described_class.new(translator:).call(Article.all, to: "de")

    expect(result).to eq(translated: 0, failed: {}, skipped: [record.id])
    expect(record.reload.body).to eq("en" => { "title" => "Hello again" })
    expect(record.translation_state).to be_nil
  end

  it "skips a record whose target was hand-written while the model answered" do
    record = article("title" => "Hello")
    stub_chat do |_payload, reply|
      Article.find(record.id).update!(body: { "en" => { "title" => "Hello" }, "de" => { "title" => "Grüß Gott" } })
      reply
    end

    result = described_class.new(translator:).call(Article.all, to: "de", force: true)

    expect(result[:skipped]).to eq([record.id])
    expect(record.reload.body["de"]).to eq("title" => "Grüß Gott")
  end

  it "writes nothing for a partially failed record, so it stays due, and reports the failed path" do
    record = article("title" => "Hello", "intro" => "Some **markdown**.")
    other = article("title" => "Bye")
    stub_chat { |_payload, reply| reply.except("#{record.id}.intro") }

    result = described_class.new(translator:).call(Article.all, to: "de")

    expect(result).to eq(translated: 1, failed: { record.id => ["intro"] }, skipped: [])
    expect(record.reload.body.keys).to eq(["en"])
    expect(record.translation_due?(:de)).to be(true)
    expect(other.reload.body["de"]).to eq("title" => "DE:Bye")
  end

  it "writes nothing for a record whose every segment failed" do
    record = article("title" => "Hello")
    stub_chat { |_payload, _reply| {} }

    result = described_class.new(translator:).call(Article.all, to: "de")

    expect(result).to eq(translated: 0, failed: { record.id => ["title"] }, skipped: [])
    expect(record.reload.body.keys).to eq(["en"])
  end

  it "writes through a custom write: callable" do
    stub_chat
    record = article("title" => "Hello")
    writes = []
    write = lambda do |target, attributes|
      writes << attributes.keys
      target.update!(attributes)
    end

    described_class.new(translator:, write:).call(Article.all, to: "de")

    expect(writes).to eq([%w[body translation_state]])
    # The save ran mark_hand_edits; the machine translation is not flagged manual.
    expect(record.reload.translation_manual?(:de)).to be(false)
    expect(record.translation_status(:de)).to eq(:current)
  end

  it "groups records by their own source locale" do
    stub_chat
    article("title" => "Hello")
    Article.create!(written_in: "sv", body: { "sv" => { "title" => "Hej" } })

    described_class.new(translator:).call(Article.all, to: "de")

    expect(calls.size).to eq(2)
  end

  it "skips a due record with no translatable text" do
    stub_chat
    record = Article.create!(body: { "en" => { "n" => 2 } })

    expect(described_class.new(translator:).call(Article.all, to: "de"))
      .to eq(translated: 0, failed: {}, skipped: [record.id])
    expect(calls).to be_empty
  end

  it "attributes segments to the right record even when ids share a dotted prefix" do
    stub_chat
    first = article("title" => "Hello", "b" => { "title" => "Nested" })
    second = article("title" => "Bye")
    allow(first).to receive(:id).and_return("a")
    allow(second).to receive(:id).and_return("a.b")

    expect { described_class.new(translator:).call([first, second], to: "de") }
      .to raise_error(Locallingo::Error, /a\.b\.title/)
  end

  it "does nothing when no record is due" do
    stub_chat

    expect(described_class.new(translator:).call(Article.none, to: "de")).to eq(translated: 0, failed: {}, skipped: [])
    expect(calls).to be_empty
  end
end
