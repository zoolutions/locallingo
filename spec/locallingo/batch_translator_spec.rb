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

  def build_translator(provider, batch_size: 20, **options)
    translator = described_class.new(provider:, model: "m", batch_size:, log: ->(*, **) {}, **options)
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

  describe "accept:" do
    let(:accept) do
      lambda do |_key, source_text, translated|
        translated.include?("{{ x }}") == source_text.include?("{{ x }}") || { "missing" => ["{{ x }}"], "extra" => [] }
      end
    end

    it "re-requests a rejected value in a fresh batch and records nothing once the retry is accepted" do
      provider = build_provider(calls) do |payload|
        calls.size == 1 ? payload.transform_values { "kaputt" } : payload.transform_values { |v| "DE:#{v}" }
      end

      translated, failed, rejections = build_translator(provider, accept:)
                                       .call({ "a" => "A {{ x }}", "b" => "B" }, %w[a b], instructions: "x")

      expect(translated).to eq("a" => "DE:A {{ x }}", "b" => "kaputt")
      expect(failed).to be_empty
      expect(rejections).to eq({})
      expect(calls).to eq([%w[a b], %w[a]])
    end

    it "reports a value still rejected after the omitted-key rounds as failed, with the reason" do
      provider = build_provider(calls) { |payload| payload.transform_values { "kaputt" } }

      translated, failed, rejections = build_translator(provider, accept:)
                                       .call({ "a" => "A {{ x }}", "b" => "B" }, %w[a b], instructions: "x")

      expect(translated).to eq("b" => "kaputt")
      expect(failed).to eq(["a"])
      expect(rejections).to eq("a" => { "missing" => ["{{ x }}"], "extra" => [] })
      expect(calls).to eq([%w[a b], %w[a], %w[a]])
    end

    it "drops a stale rejection when the key is omitted in a later round" do
      provider = build_provider(calls) do |payload|
        calls.size == 1 ? payload.transform_values { "kaputt" } : {}
      end

      _translated, failed, rejections = build_translator(provider, accept:)
                                        .call({ "a" => "A {{ x }}" }, %w[a], instructions: "x")

      expect(failed).to eq(["a"])
      expect(rejections).to eq({})
    end

    it "passes the key, the source text and the reply to accept" do
      seen = []
      provider = build_provider(calls) { |payload| payload.transform_values { |v| "DE:#{v}" } }

      accept = lambda do |*args|
        seen << args
        true
      end
      build_translator(provider, accept:).call({ "a" => "A" }, ["a"], instructions: "x")

      expect(seen).to eq([["a", "A", "DE:A"]])
    end

    it "returns no rejections without accept:, and two-element destructuring keeps working" do
      provider = build_provider(calls) { |payload| payload.transform_values { |v| "DE:#{v}" } }

      result = build_translator(provider).call({ "a" => "A" }, ["a"], instructions: "x")
      translated, failed = result

      expect(result.last).to eq({})
      expect([translated, failed]).to eq([{ "a" => "DE:A" }, []])
    end
  end

  describe "max_batch_chars" do
    let(:echo) { build_provider(calls) { |payload| payload.transform_values { |v| "DE:#{v}" } } }

    it "closes a batch once the next value would exceed the character budget" do
      source = { "a" => "x" * 40, "b" => "x" * 40, "c" => "x" * 40, "d" => "x" * 10 }

      translated, = build_translator(echo, max_batch_chars: 100).call(source, source.keys, instructions: "x")

      expect(calls).to eq([%w[a b], %w[c d]])
      expect(translated.keys).to eq(source.keys)
    end

    it "still closes a batch at batch_size keys" do
      build_translator(echo, batch_size: 3, max_batch_chars: 10_000).call(source, source.keys, instructions: "x")

      expect(calls).to eq([%w[a b c], %w[d e f], %w[g h]])
    end

    it "sends a single oversized value alone" do
      source = { "a" => "short", "b" => "x" * 500, "c" => "short" }

      build_translator(echo, max_batch_chars: 100).call(source, source.keys, instructions: "x")

      expect(calls).to eq([%w[a], %w[b], %w[c]])
    end

    it "counts keys only when no budget is given" do
      build_translator(echo, batch_size: 5).call(source, source.keys, instructions: "x")

      expect(calls).to eq([%w[a b c d e], %w[f g h]])
    end
  end

  describe "pause" do
    let(:echo) { build_provider(calls) { |payload| payload.transform_values { |v| "DE:#{v}" } } }

    it "sleeps BASE_SLEEP_DURATION after each batch by default" do
      translator = build_translator(echo, batch_size: 4)
      translator.call(source, source.keys, instructions: "x")

      expect(translator).to have_received(:sleep).with(described_class::BASE_SLEEP_DURATION).twice
    end

    it "sleeps the configured pause after each batch" do
      translator = build_translator(echo, batch_size: 4, pause: 0.25)
      translator.call(source, source.keys, instructions: "x")

      expect(translator).to have_received(:sleep).with(0.25).twice
    end

    it "never sleeps with pause: 0 when every batch succeeds" do
      translator = build_translator(echo, batch_size: 4, pause: 0)
      translator.call(source, source.keys, instructions: "x")

      expect(translator).not_to have_received(:sleep)
    end
  end
end
