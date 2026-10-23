# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::Prompt do
  # Fixtures captured from Manager#translation_prompt before the prompt moved
  # here: the CLI's prompt must stay byte-identical.
  def fixture(name) = File.read(File.expand_path("../fixtures/#{name}", __dir__))

  def config_with(overrides)
    base = Locallingo::Configuration.new(root_path: Dir.pwd).data
    Locallingo::Configuration.new(root_path: Dir.pwd, data: base.merge(overrides))
  end

  let(:config) do
    config_with(
      "context" => "a booking platform for clinics",
      "placeholder_style" => "%{name}",
      "glossary" => { "Workspace" => "the tenant account", "Seat" => "a paid user licence" },
      "language_guides" => { "de" => "## German\n- Use \"Sie\", never \"du\"." }
    )
  end

  describe ".translation with style: :ui" do
    it "equals the 0.5.0 Manager prompt byte for byte" do
      expect(described_class.translation(config:, from: "en", to: "de")).to eq(fixture("ui_prompt_de.txt"))
    end

    it "equals the 0.5.0 prompt without glossary or language guide" do
      bare = config_with("glossary" => {}, "language_guides" => {})

      expect(described_class.translation(config: bare, from: "en", to: "sv")).to eq(fixture("ui_prompt_sv_bare.txt"))
    end

    it "is what Manager sends to the provider" do
      prompts = []
      stub_llm_chat do |payload:, instructions:, **|
        prompts << instructions
        payload.transform_values { |v| "DE:#{v}" }
      end
      locales = { "en" => { "greeting" => { "hi" => "Hello" } } }

      with_app(locales:, config: { "after_translate" => [] }) do |root|
        manager = Locallingo::Manager.new(config: config_for(root), logger: Logger.new(nil))
        allow(manager.send(:batch_translator)).to receive(:sleep)
        manager.translate!

        expect(prompts).to eq([described_class.translation(config: config_for(root), from: "en", to: "de")])
      end
    end
  end

  describe ".translation with style: :prose" do
    subject(:prompt) { described_class.translation(config:, from: "en", to: "de", style: :prose) }

    it "drops the UI brevity rule" do
      expect(prompt).not_to include("UI space is limited")
    end

    it "asks to keep the Markdown structure and link targets" do
      expect(prompt).to include("Keep the Markdown structure", "never the link target", "Never merge or split values")
    end

    it "keeps the glossary and the language guide" do
      expect(prompt).to include('"Workspace" = the tenant account', 'Use "Sie", never "du".')
    end
  end

  describe "instructions" do
    it "appends caller instructions after the language guide under their own heading" do
      prompt = described_class.translation(config:, from: "en", to: "de", instructions: "Write in a warm, plain voice.")

      expect(prompt).to include("## Additional Instructions\nWrite in a warm, plain voice.")
      expect(prompt.index("Additional Instructions")).to be > prompt.index('never "du"')
      expect(prompt.index("Additional Instructions")).to be < prompt.index("Return ONLY")
    end

    it "ignores blank instructions" do
      expect(described_class.translation(config:, from: "en", to: "de", instructions: "  "))
        .to eq(fixture("ui_prompt_de.txt"))
    end
  end

  describe "placeholders" do
    let(:patterns) { [/\{\{.*?\}\}/m, /\{%.*?%\}/m] }

    it "adds a token rule under General Rules, after the placeholder_style line, naming each pattern's source" do
      prompt = described_class.translation(config:, from: "en", to: "de", placeholders: patterns)
      rule = "- Preserve every token matching these patterns exactly as it appears, with the same count: " \
             "`\\{\\{.*?\\}\\}`, `\\{%.*?%\\}`\n"

      expect(prompt).to include("- Preserve placeholders like %{name} exactly as they appear\n#{rule}" \
                                "- Preserve HTML tags if present")
      expect(prompt.index(rule)).to be < prompt.index("## Terminology")
    end

    it "adds the rule to the :prose prompt too" do
      prompt = described_class.translation(config:, from: "en", to: "de", style: :prose, placeholders: patterns)

      expect(prompt).to include("Preserve every token matching these patterns")
    end

    it "keeps the prompt byte-identical without patterns" do
      [[], nil].each do |placeholders|
        expect(described_class.translation(config:, from: "en", to: "de", placeholders:))
          .to eq(fixture("ui_prompt_de.txt"))
      end
    end

    it "wraps a single Regexp" do
      expect(described_class.translation(config:, from: "en", to: "de", placeholders: patterns.first))
        .to include("with the same count: `\\{\\{.*?\\}\\}`\n")
    end
  end

  it "rejects an unknown or nil style" do
    [:poem, nil].each do |style|
      expect { described_class.translation(config:, from: "en", to: "de", style:) }
        .to raise_error(Locallingo::Error, /style/)
    end
  end

  it "accepts the style as a String" do
    expect(described_class.translation(config:, from: "en", to: "de", style: "ui")).to eq(fixture("ui_prompt_de.txt"))
  end
end
