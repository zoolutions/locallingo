# frozen_string_literal: true

# `Locallingo.settings` is boot-time state: written by `Locallingo.configure`
# (a Rails initializer, or the CLI's `.locallingo.rb`), read on every LLM call.
# Each configure publishes a frozen copy, so readers on any thread or Ractor
# only ever see finished settings (#35).
RSpec.describe Locallingo::Settings do
  context "with the default settings" do
    it_behaves_like "a boot-finalized configuration", readers: [Locallingo.method(:settings)]
  end

  context "with String keys set through configure" do
    # An unfrozen String, as ENV.fetch or a credentials store returns it.
    it_behaves_like "a boot-finalized configuration",
                    readers: [Locallingo.method(:settings)],
                    finalize: -> { Locallingo.configure { |c| c.anthropic_api_key = +"sk-ant-123" } }
  end

  describe "Locallingo.configure" do
    it "publishes frozen settings" do
      Locallingo.configure { |c| c.anthropic_api_key = +"sk-ant-123" }

      expect(Locallingo.settings).to be_frozen
      expect(Locallingo.settings.anthropic_api_key).to be_frozen.and eq("sk-ant-123")
    end

    it "refuses writes outside configure" do
      expect { Locallingo.settings.anthropic_api_key = "sneaky" }.to raise_error(FrozenError)
    end

    it "keeps earlier keys when called again" do
      Locallingo.configure { |c| c.anthropic_api_key = "first" }
      Locallingo.configure { |c| c.openai_api_key = "second" }

      expect(Locallingo.settings.api_key_for(:anthropic)).to eq("first")
      expect(Locallingo.settings.api_key_for(:openai)).to eq("second")
    end

    it "never exposes half-configured settings to a concurrent reader" do
      seen = Queue.new
      configuring = Queue.new
      resume = Queue.new
      writer = Thread.new do
        Locallingo.configure do |c|
          c.anthropic_api_key = "new-anthropic"
          configuring << true
          resume.pop
          c.openai_api_key = "new-openai"
        end
      end
      configuring.pop
      seen << Locallingo.settings.api_key_for(:anthropic)
      resume << true
      writer.join

      expect(seen.pop).to be_nil
      expect(Locallingo.settings.api_key_for(:openai)).to eq("new-openai")
    end

    it "keeps a callable key as is, resolved on every use" do
      keys = %w[first-key rotated-key].each
      Locallingo.configure { |c| c.anthropic_api_key = -> { keys.next } }

      expect([Locallingo.settings.api_key_for(:anthropic), Locallingo.settings.api_key_for(:anthropic)])
        .to eq(%w[first-key rotated-key])
    end
  end

  describe "Locallingo.reset_settings!" do
    it "restores frozen, blank defaults" do
      Locallingo.configure { |c| c.anthropic_api_key = "key" }

      Locallingo.reset_settings!

      expect(Locallingo.settings).to be_frozen
      expect(Locallingo.settings.api_key_for(:anthropic)).to be_nil
    end
  end
end
