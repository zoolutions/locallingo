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
    let(:contexts) { [] }

    before do
      allow(RubyLLM::Chat).to receive(:new) do |context: nil, **|
        contexts << context
        conversation
      end
      allow(conversation).to receive_messages(with_instructions: conversation, ask: response)
    end

    def chat!
      provider.chat(model: "claude-x", instructions: "translate", payload: { "greeting" => "hello" })
    end

    # The key the chat ran with, from the context it was built on.
    def chat_key = contexts.last.config.anthropic_api_key

    it "marks the system prompt as a prompt cache boundary" do
      chat!

      expect(conversation).to have_received(:with_instructions).with("translate", cache_until_here: true)
    end

    it "sets a cache boundary RubyLLM itself accepts on the system message" do
      Locallingo.configure { |c| c.anthropic_api_key = "test-key" }
      real_chat = nil
      allow(RubyLLM::Chat).to receive(:new).and_wrap_original do |original, **kwargs|
        real_chat = original.call(**kwargs)
        allow(real_chat).to receive(:ask).and_return(response)
        real_chat
      end

      chat!

      system_message = real_chat.messages.find { |message| message.role == :system }
      expect(system_message.cache_until_here?).to be(true)
    end

    it "chats on a context of its own, never through the global RubyLLM.chat" do
      allow(RubyLLM).to receive(:chat)

      chat!

      expect(contexts.last).to be_a(RubyLLM::Context)
      expect(RubyLLM).not_to have_received(:chat)
    end

    it "chats with the ENV key and leaves the global config alone" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key-123"))

      result = chat!

      expect(chat_key).to eq("env-key-123")
      expect(RubyLLM.config.anthropic_api_key).to be_nil
      expect(result).to eq({ "greeting" => "hallo" })
    end

    it "keeps a key the host app already configured over ENV" do
      RubyLLM.config.anthropic_api_key = "explicit-app-key"
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key-123"))

      chat!

      expect(chat_key).to eq("explicit-app-key")
      expect(RubyLLM.config.anthropic_api_key).to eq("explicit-app-key")
    end

    it "leaves the key unset when the ENV var is absent" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))

      chat!

      expect(chat_key).to be_nil
      expect(RubyLLM.config.anthropic_api_key).to be_nil
    end

    it "uses a Locallingo settings key over a host-configured one without writing it back" do
      RubyLLM.config.anthropic_api_key = "explicit-app-key"
      Locallingo.configure { |c| c.anthropic_api_key = "settings-key" }

      chat!

      expect(chat_key).to eq("settings-key")
      expect(RubyLLM.config.anthropic_api_key).to eq("explicit-app-key")
    end

    it "resolves a callable settings key at chat time" do
      RubyLLM.config.anthropic_api_key = nil
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))
      keys = %w[first-key rotated-key]
      Locallingo.configure { |c| c.anthropic_api_key = -> { keys.shift } }

      chat!
      first = chat_key
      chat!

      expect([first, chat_key]).to eq(%w[first-key rotated-key])
      expect(RubyLLM.config.anthropic_api_key).to be_nil
    end
  end

  describe "with a RubyLLM::Context" do
    let(:response) { double(content: '{"greeting":"hallo"}') }

    def context_with(key) = RubyLLM.context { |config| config.anthropic_api_key = key }

    def stub_context_chat(context)
      conversation = double
      allow(conversation).to receive_messages(with_instructions: conversation, ask: response)
      allow(context).to receive(:chat).and_return(conversation)
      conversation
    end

    before do
      RubyLLM.config.anthropic_api_key = "global-key"
      allow(RubyLLM).to receive(:chat)
    end

    it "chats through the context and never touches the global config" do
      Locallingo.configure { |c| c.anthropic_api_key = "settings-key" }
      context = context_with("tenant-key")
      stub_context_chat(context)
      provider = described_class.new(provider: :anthropic, context:)

      result = provider.chat(model: "claude-x", instructions: "translate", payload: { "greeting" => "hello" })

      expect(result).to eq("greeting" => "hallo")
      expect(context).to have_received(:chat).with(model: "claude-x", provider: :anthropic, assume_model_exists: true)
      expect(RubyLLM).not_to have_received(:chat)
      expect(RubyLLM.config.anthropic_api_key).to eq("global-key")
    end

    it "keeps two translators' credentials apart when they run concurrently" do
      contexts = [context_with("tenant-a"), context_with("tenant-b")]
      contexts.each { |context| stub_context_chat(context) }
      allow(RubyLLM.config).to receive(:anthropic_api_key=)

      contexts.map do |context|
        Thread.new do
          described_class.new(provider: :anthropic, context:)
                         .chat(model: "m", instructions: "x", payload: { "a" => "b" })
        end
      end.each(&:join)

      expect(contexts.map { |c| c.config.anthropic_api_key }).to eq(%w[tenant-a tenant-b])
      expect(RubyLLM.config).not_to have_received(:anthropic_api_key=)
    end

    it "checks credentials against the context only" do
      stub_const("ENV", ENV.to_h.merge("ANTHROPIC_API_KEY" => "env-key"))

      expect(described_class.new(provider: :anthropic, context: context_with("tenant-key")).credentials?).to be(true)
      expect(described_class.new(provider: :anthropic, context: context_with(nil)).credentials?).to be(false)
    end

    it "names the context when it has no key" do
      provider = described_class.new(provider: :anthropic, context: context_with(""))

      expect { provider.ensure_credentials! }
        .to raise_error(Locallingo::MissingCredentialsError, /RubyLLM context has no anthropic_api_key/)
    end
  end
end
