# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::Translator do
  let(:config) do
    base = Locallingo::Configuration.new(root_path: Dir.pwd).data
    Locallingo::Configuration.new(
      root_path: Dir.pwd,
      data: base.merge(
        "provider" => "anthropic",
        "glossary" => { "Workspace" => "the tenant account" },
        "language_guides" => { "de" => "Use \"Sie\"." }
      )
    )
  end
  let(:calls) { [] }
  let(:texts) { { "title" => "Hello", "intro" => "Some **markdown**." } }

  def build(**options) = described_class.new(config:, pause: 0, logger: Logger.new(nil), **options)

  def stub_chat(&responder)
    stub_llm_chat do |payload:, model:, instructions:|
      calls << { payload:, model:, instructions: }
      responder ? yield(payload) : payload.transform_values { |v| "DE:#{v}" }
    end
  end

  it "translates a plain key => text hash and reports no failures" do
    stub_chat

    result = build.translate(texts, from: "en", to: "de")

    expect(result.translations).to eq("title" => "DE:Hello", "intro" => "DE:Some **markdown**.")
    expect(result.failed).to eq([])
  end

  it "sends the configured prompt with style and caller instructions" do
    stub_chat

    build.translate(texts, from: "en", to: "de", style: :prose, instructions: "Warm voice.")

    expected = Locallingo::Prompt.translation(config:, from: "en", to: "de", style: :prose, instructions: "Warm voice.")
    expect(calls.map { |c| c[:instructions] }.uniq).to eq([expected])
    expect(expected).to include("the tenant account", 'Use "Sie".', "Warm voice.")
  end

  it "uses the configured model unless overridden" do
    stub_chat

    build.translate(texts, from: "en", to: "de")
    build(model: "claude-other").translate(texts, from: "en", to: "de")

    expect(calls.map { |c| c[:model] }).to eq([config.translate_model, "claude-other"])
  end

  it "drops keys the model invents" do
    stub_chat { |payload| payload.transform_values { |v| "DE:#{v}" }.merge("invented" => "Böse") }

    expect(build.translate(texts, from: "en", to: "de").translations.keys).to match_array(texts.keys)
  end

  it "reports keys that failed after BatchTranslator's retries" do
    stub_chat { |payload| payload.except("intro").transform_values { |v| "DE:#{v}" } }

    result = build.translate(texts, from: "en", to: "de")

    expect(result.translations).to eq("title" => "DE:Hello")
    expect(result.failed).to eq(["intro"])
  end

  it "applies max_batch_chars from the options" do
    stub_chat

    build(max_batch_chars: 6).translate(texts, from: "en", to: "de")

    expect(calls.map { |c| c[:payload].keys }).to eq([["title"], ["intro"]])
  end

  it "raises when two keys collapse to the same string" do
    stub_chat

    expect { build.translate({ :title => "A", "title" => "B" }, from: "en", to: "de") }
      .to raise_error(Locallingo::Error, /"title"/)
    expect(calls).to be_empty
  end

  it "sends nothing for blank texts or an empty hash" do
    stub_chat

    result = build.translate({ "a" => "", "b" => "  " }, from: "en", to: "de")

    expect(result.translations).to eq({})
    expect(result.failed).to eq([])
    expect(calls).to be_empty
  end

  it "raises MissingCredentialsError before any call" do
    stub_chat
    stub_llm_missing_credentials

    expect { build.translate(texts, from: "en", to: "de") }.to raise_error(Locallingo::MissingCredentialsError)
    expect(calls).to be_empty
  end

  it "raises before any call when the context holds no key" do
    require "ruby_llm"
    context = RubyLLM.context { |c| c.anthropic_api_key = nil }
    allow(context).to receive(:chat)

    expect { build(context:).translate(texts, from: "en", to: "de") }
      .to raise_error(Locallingo::MissingCredentialsError, /RubyLLM context/)
    expect(context).not_to have_received(:chat)
  end

  it "chats through the given context" do
    require "ruby_llm"
    context = RubyLLM.context { |c| c.anthropic_api_key = "tenant-key" }
    conversation = double
    allow(conversation).to receive_messages(with_instructions: conversation, ask: double(content: '{"title":"Hallo"}'))
    allow(context).to receive(:chat).and_return(conversation)

    result = build(context:).translate({ "title" => "Hello" }, from: "en", to: "de")

    expect(result.translations).to eq("title" => "Hallo")
    expect(context).to have_received(:chat)
  end
end
