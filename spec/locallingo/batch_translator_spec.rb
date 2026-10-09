# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::BatchTranslator do
  # A provider double whose #chat records each payload and answers via the block.
  def build_provider(calls)
    provider = Object.new
    provider.define_singleton_method(:chat) do |payload:, **|
      calls << payload.keys
      yield(payload)
    end
    provider
  end

  def build_translator(provider, batch_size: 20)
    translator = described_class.new(provider:, model: "m", batch_size:, log: ->(*, **) {})
    allow(translator).to receive(:sleep)
    translator
  end

  let(:source) { %w[a b c d e f g h].to_h { |k| [k, "Text #{k}"] } }
  let(:calls) { [] }

  it "halves an unparseable batch until only the bad key fails" do
    provider = build_provider(calls) do |payload|
      raise JSON::ParserError, "unexpected token" if payload.key?("c")

      payload.transform_values { |v| "DE:#{v}" }
    end

    translated, failed = build_translator(provider).call(source, source.keys, instructions: "x")

    expect(failed).to eq(["c"])
    expect(translated.keys).to match_array(source.keys - ["c"])
    # 8 → 4+4 → 2+2 → 1+1: never the identical payload twice.
    expect(calls).to eq([%w[a b c d e f g h], %w[a b c d], %w[a b], %w[c d], %w[c], %w[d], %w[e f g h]])
  end

  it "does not resend a single unparseable key in the missing-key rounds" do
    provider = build_provider(calls) { |_payload| raise JSON::ParserError, "unexpected token" }

    _translated, failed = build_translator(provider).call({ "a" => "A" }, ["a"], instructions: "x")

    expect(failed).to eq(["a"])
    expect(calls).to eq([["a"]])
  end

  it "retries a transport error on the same payload with backoff" do
    provider = build_provider(calls) do |payload|
      raise StandardError, "503 Service Unavailable" if calls.size == 1

      payload.transform_values { |v| "DE:#{v}" }
    end
    translator = build_translator(provider)

    translated, failed = translator.call({ "a" => "A" }, ["a"], instructions: "x")

    expect(translated).to eq("a" => "DE:A")
    expect(failed).to be_empty
    expect(calls).to eq([["a"], ["a"]])
    expect(translator).to have_received(:sleep).with(described_class::BASE_SLEEP_DURATION * 2)
  end

  it "gives up after MAX_RETRIES transport errors and reports the keys as failed" do
    provider = build_provider(calls) { |_payload| raise StandardError, "timeout" }

    _translated, failed = build_translator(provider).call({ "a" => "A" }, ["a"], instructions: "x")

    expect(failed).to eq(["a"])
    # Each of the 1 + MAX_MISSING_RETRIES rounds retries MAX_RETRIES times.
    expect(calls.size).to eq(described_class::MAX_RETRIES * (1 + described_class::MAX_MISSING_RETRIES))
  end

  it "re-batches keys the model omitted" do
    provider = build_provider(calls) do |payload|
      calls.size == 1 ? { "a" => "DE:A" } : payload.transform_values { |v| "DE:#{v}" }
    end

    translated, failed = build_translator(provider).call(source.slice("a", "b"), %w[a b], instructions: "x")

    expect(translated).to eq("a" => "DE:A", "b" => "DE:Text b")
    expect(failed).to be_empty
    expect(calls).to eq([%w[a b], %w[b]])
  end
end
