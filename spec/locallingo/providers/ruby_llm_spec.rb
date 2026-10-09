# frozen_string_literal: true

require "ruby_llm"

RSpec.describe Locallingo::Providers::RubyLLM do
  subject(:provider) { described_class.new(provider: :anthropic) }

  around do |example|
    original = RubyLLM.config.anthropic_api_key
    example.run
  ensure
    RubyLLM.config.anthropic_api_key = original
  end

  describe "#credentials?" do
    before do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))
    end

    it "is true when only Locallingo settings holds a key" do
      Locallingo.configure { |c| c.anthropic_api_key = "settings-key" }
      expect(provider.credentials?).to be(true)
    end

    it "is true when only the host RubyLLM config holds a key" do
      RubyLLM.config.anthropic_api_key = "host-key"
      expect(provider.credentials?).to be(true)
    end

    it "is true when only ENV holds a key" do
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key"))
      expect(provider.credentials?).to be(true)
    end

    it "is false when every source is blank" do
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "  "))
      Locallingo.configure { |c| c.anthropic_api_key = -> { "" } }
      expect(provider.credentials?).to be(false)
    end

    it "stays permissive for providers without a known credential ENV var" do
      expect(described_class.new(provider: :ollama).credentials?).to be(true)
    end

    it "answers from ENV without ruby_llm loaded" do
      hide_const("RubyLLM")
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key"))
      expect(provider.credentials?).to be(true)
    end
  end

  describe "#ensure_credentials!" do
    it "raises naming every way to provide a key" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))

      expect { provider.ensure_credentials! }.to raise_error(
        Locallingo::MissingCredentialsError,
        /ANTHROPIC_API_KEY.*Locallingo\.configure.*\.locallingo\.rb/m
      )
    end
  end

  describe "#chat" do
    let(:conversation) { double }
    let(:response) { double(content: '{"greeting":"hallo"}') }

    before do
      allow(RubyLLM).to receive(:chat).and_return(conversation)
      allow(conversation).to receive_messages(with_instructions: conversation, ask: response)
    end

    def chat!
      provider.chat(model: "claude-x", instructions: "translate", payload: { "greeting" => "hello" })
    end

    it "marks the system prompt as a prompt cache boundary" do
      chat!

      expect(conversation).to have_received(:with_instructions).with("translate", cache_until_here: true)
    end

    it "configures the provider API key from ENV before chatting" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key-123"))

      result = chat!

      expect(RubyLLM.config.anthropic_api_key).to eq("env-key-123")
      expect(result).to eq({ "greeting" => "hallo" })
    end

    it "does not clobber a key the host app already configured" do
      RubyLLM.config.anthropic_api_key = "explicit-app-key"
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key-123"))

      chat!

      expect(RubyLLM.config.anthropic_api_key).to eq("explicit-app-key")
    end

    it "leaves configuration untouched when the ENV var is absent" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))

      chat!

      expect(RubyLLM.config.anthropic_api_key).to be_nil
    end

    it "pushes a Locallingo settings key over a host-configured one" do
      RubyLLM.config.anthropic_api_key = "explicit-app-key"
      Locallingo.configure { |c| c.anthropic_api_key = "settings-key" }

      chat!

      expect(RubyLLM.config.anthropic_api_key).to eq("settings-key")
    end

    it "resolves a callable settings key at chat time" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))
      Locallingo.configure { |c| c.anthropic_api_key = -> { "lazy-key" } }

      chat!

      expect(RubyLLM.config.anthropic_api_key).to eq("lazy-key")
    end
  end
end
