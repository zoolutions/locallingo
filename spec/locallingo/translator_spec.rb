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

  describe "placeholders:" do
    let(:liquid) { [/\{\{.*?\}\}/m, /\{%.*?%\}/m] }
    let(:texts) do
      { "subject" => "Finish setting up {{ item.name }}",
        "body" => "{% paragraph %}Your {{ item.name }} is ready.{% endparagraph %}" }
    end
    let(:good) do
      { "subject" => "Richten Sie {{ item.name }} fertig ein",
        "body" => "{% paragraph %}Ihr {{ item.name }} ist bereit.{% endparagraph %}" }
    end

    before { stub_const("Locallingo::BatchTranslator::BASE_SLEEP_DURATION", 0) }

    it "accepts a reply that keeps every token" do
      stub_chat { |payload| good.slice(*payload.keys) }

      result = build.translate(texts, from: "en", to: "de", placeholders: liquid)

      expect(result.translations).to eq(good)
      expect(result.failed).to eq([])
      expect(result.rejections).to eq({})
    end

    it "re-requests a reply with a translated token and accepts a retry that keeps the tokens" do
      stub_chat do |payload|
        next good.slice(*payload.keys) unless calls.size == 1

        good.merge("subject" => "Richten Sie {{ artikel.name }} fertig ein")
      end

      result = build.translate(texts, from: "en", to: "de", placeholders: liquid)

      expect(calls.map { |c| c[:payload].keys }).to eq([%w[subject body], %w[subject]])
      expect(result.translations).to eq(good)
      expect(result.failed).to eq([])
      expect(result.rejections).to eq({})
    end

    it "reports a reply that still differs after the rounds as failed, never as a translation" do
      broken = good.merge("body" => "Ihr {{ item.name }} ist bereit.{% endparagraph %}")
      stub_chat { |payload| broken.slice(*payload.keys) }

      result = build.translate(texts, from: "en", to: "de", placeholders: liquid)

      expect(result.translations).to eq(good.slice("subject"))
      expect(result.failed).to eq(["body"])
      expect(result.rejections).to eq("body" => { "missing" => ["{% paragraph %}"], "extra" => [] })
      expect(calls.size).to eq(1 + Locallingo::BatchTranslator::MAX_MISSING_RETRIES)
    end

    it "wraps a single Regexp" do
      stub_chat { |payload| payload.transform_values { "kaputt" } }

      result = build.translate(texts.slice("subject"), from: "en", to: "de", placeholders: liquid.first)

      expect(result.rejections).to eq("subject" => { "missing" => ["{{ item.name }}"], "extra" => [] })
    end

    it "names the patterns in the prompt" do
      stub_chat { |payload| good.slice(*payload.keys) }

      build.translate(texts, from: "en", to: "de", style: :prose, placeholders: liquid)

      expected = Locallingo::Prompt.translation(config:, from: "en", to: "de", style: :prose, placeholders: liquid)
      expect(calls.map { |c| c[:instructions] }.uniq).to eq([expected])
    end

    it "defaults to translate.placeholders" do
      configured = Locallingo::Configuration.new(
        root_path: Dir.pwd, data: config.data.merge("translate" => config.data["translate"].merge(
          "placeholders" => ['\{\{.*?\}\}']
        ))
      )
      stub_chat { |payload| payload.transform_values { "kaputt" } }

      result = described_class.new(config: configured, pause: 0, logger: Logger.new(nil))
                              .translate(texts.slice("subject"), from: "en", to: "de")

      expect(result.failed).to eq(["subject"])
      expect(calls.first[:instructions]).to include("`\\{\\{.*?\\}\\}`")
    end

    it "checks nothing and sends today's prompt without placeholders or config" do
      stub_chat { |payload| payload.transform_values { "kaputt" } }

      result = build.translate(texts, from: "en", to: "de")

      expect(result.translations).to eq("subject" => "kaputt", "body" => "kaputt")
      expect(result.rejections).to eq({})
      expect(calls.first[:instructions]).to eq(Locallingo::Prompt.translation(config:, from: "en", to: "de"))
      expect(calls.first[:instructions]).not_to include("Preserve every token")
    end

    it "rejects a pattern that is not a Regexp" do
      stub_chat

      expect { build.translate(texts, from: "en", to: "de", placeholders: ["{{"]) }
        .to raise_error(Locallingo::Error, /placeholders/)
      expect(calls).to be_empty
    end
  end
end
