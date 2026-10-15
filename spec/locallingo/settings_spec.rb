# frozen_string_literal: true

RSpec.describe Locallingo::Settings do
  subject(:settings) { described_class.new }

  it "has an accessor pair for every supported provider" do
    described_class::PROVIDERS.each do |provider|
      settings.public_send("#{provider}_api_key=", "key-#{provider}")
      expect(settings.public_send("#{provider}_api_key")).to eq("key-#{provider}")
    end
  end

  it "stays in sync with the provider credential map" do
    expect(described_class::PROVIDERS)
      .to match_array(Locallingo::Providers::RubyLLM::CREDENTIAL_ENV.keys)
  end

  describe "#api_key_for" do
    it "returns the configured key, stripped" do
      settings.anthropic_api_key = "  sk-ant-123  "
      expect(settings.api_key_for(:anthropic)).to eq("sk-ant-123")
    end

    it "returns nil when no key is set" do
      expect(settings.api_key_for(:anthropic)).to be_nil
    end

    it "returns nil for blank keys" do
      settings.anthropic_api_key = "   "
      expect(settings.api_key_for(:anthropic)).to be_nil
    end

    it "returns nil for unknown providers" do
      expect(settings.api_key_for(:ollama)).to be_nil
    end

    it "resolves a callable lazily on every call" do
      keys = %w[first-key second-key].each
      settings.anthropic_api_key = -> { keys.next }

      expect(settings.api_key_for(:anthropic)).to eq("first-key")
      expect(settings.api_key_for(:anthropic)).to eq("second-key")
    end

    it "returns nil when a callable resolves to a blank value" do
      settings.anthropic_api_key = -> { "" }
      expect(settings.api_key_for(:anthropic)).to be_nil
    end

    it "lets a raising callable propagate" do
      settings.anthropic_api_key = -> { raise "vault unreachable" }
      expect { settings.api_key_for(:anthropic) }.to raise_error("vault unreachable")
    end
  end

  describe "Locallingo.configure" do
    it "yields settings and returns the ones it published" do
      returned = Locallingo.configure { |c| c.anthropic_api_key = "block-key" }

      expect(returned).to be(Locallingo.settings)
      expect(Locallingo.settings.anthropic_api_key).to eq("block-key")
    end

    it "returns the same settings across calls and resets with reset_settings!" do
      first = Locallingo.settings
      expect(Locallingo.settings).to be(first)

      Locallingo.reset_settings!
      expect(Locallingo.settings).not_to be(first)
    end
  end
end
