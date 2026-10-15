# frozen_string_literal: true

require "ruby_llm"

# Without a RubyLLM::Context passed in, the provider builds one per chat from the
# resolved key, so the process-global RubyLLM.config is never written and two
# translators with different keys cannot see each other's (#35).
RSpec.describe Locallingo::Providers::RubyLLM do
  context "without a given context" do
    let(:config) do
      base = Locallingo::Configuration.new(root_path: Dir.pwd).data
      Locallingo::Configuration.new(root_path: Dir.pwd, data: base.merge("provider" => "anthropic"))
    end
    let(:conversation) { double }

    around do |example|
      original = RubyLLM.config.anthropic_api_key
      RubyLLM.config.anthropic_api_key = nil
      example.run
    ensure
      RubyLLM.config.anthropic_api_key = original
    end

    before do
      stub_const("ENV", ENV.to_h.except("ANTHROPIC_API_KEY"))
      allow(RubyLLM.config).to receive(:anthropic_api_key=).and_call_original
      allow(conversation).to receive(:with_instructions).and_return(conversation)
      allow(conversation).to receive(:ask) do |json|
        double(content: JSON.generate(JSON.parse(json).transform_values { |text| "DE:#{text}" }))
      end
    end

    # The key a chat runs with: its context's, else the global config's.
    def key_of(context) = (context&.config || RubyLLM.config).anthropic_api_key

    def translator = Locallingo::Translator.new(config:, pause: 0, logger: Logger.new(nil))

    it "never lets two concurrent translators observe each other's key" do
      # Per-tenant keys through one callable, resolved on each translator's thread.
      Locallingo.configure { |c| c.anthropic_api_key = -> { Thread.current[:locallingo_spec_key] } }
      seen = {}
      a_building = Queue.new
      b_built = Queue.new
      # Force the race window: A starts building its chat, then B builds its own
      # in full, then A reads its key. With a shared global config A reads B's key.
      allow(RubyLLM::Chat).to receive(:new) do |context: nil, **|
        tenant = Thread.current[:locallingo_spec_key]
        if tenant == "key-a"
          a_building << true
          b_built.pop
        else
          a_building.pop
        end
        seen[tenant] = key_of(context)
        b_built << true if tenant == "key-b"
        conversation
      end

      results = %w[key-a key-b].map do |key|
        Thread.new do
          Thread.current[:locallingo_spec_key] = key
          translator.translate({ "hi" => "Hello" }, from: "en", to: "de").translations
        end
      end.map(&:value)

      expect(results).to eq([{ "hi" => "DE:Hello" }] * 2)
      expect(seen).to eq("key-a" => "key-a", "key-b" => "key-b")
      expect(RubyLLM.config).not_to have_received(:anthropic_api_key=)
    end

    it "runs each chat on its own context carrying the resolved key" do
      Locallingo.configure { |c| c.anthropic_api_key = "settings-key" }
      contexts = []
      allow(RubyLLM::Chat).to receive(:new) do |context: nil, **|
        contexts << context
        conversation
      end

      2.times { translator.translate({ "hi" => "Hello" }, from: "en", to: "de") }

      expect(contexts).to all(be_a(RubyLLM::Context))
      expect(contexts.uniq.size).to eq(2)
      expect(contexts.map { |context| key_of(context) }).to eq(%w[settings-key settings-key])
      expect(RubyLLM.config).not_to have_received(:anthropic_api_key=)
    end
  end
end
