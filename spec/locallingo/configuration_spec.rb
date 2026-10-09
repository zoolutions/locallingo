# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::Configuration do
  it "falls back to shipped defaults when no config file exists" do
    Dir.mktmpdir do |root|
      config = described_class.load(root_path: root)
      expect(config.source_locale).to eq("en")
      expect(config.target_locales).to eq(%w[de sv])
      expect(config.provider).to eq(:openai)
    end
  end

  it "merges user defaults over shipped defaults" do
    with_app(locales: {}, config: { "target_locales" => %w[fr af], "provider" => "anthropic" }) do |root|
      config = config_for(root)
      expect(config.target_locales).to eq(%w[fr af])
      expect(config.provider).to eq(:anthropic)
      # untouched keys keep shipped defaults
      expect(config.batch_size).to eq(20)
    end
  end

  it "deep-merges a package override onto defaults" do
    raw = <<~YAML
      defaults:
        target_locales: [de, sv]
        context: "the whole app"
        quality:
          model: gpt-4o-mini
          british_spellings: false
      packages:
        - path: engines/billing
          context: "the billing engine"
          target_locales: [de]
          quality:
            british_spellings: true
    YAML

    with_app(locales: {}, raw_config: raw) do |root|
      default = config_for(root)
      pkg = config_for(root, package: "engines/billing")

      expect(default.context).to eq("the whole app")
      expect(pkg.context).to eq("the billing engine")
      expect(pkg.target_locales).to eq(%w[de])
      # deep merge keeps sibling quality keys from defaults
      expect(pkg.quality_model).to eq("gpt-4o-mini")
      expect(pkg.british_spellings?).to be(true)
      # package path scopes locales_dir under the package
      expect(pkg.locales_dir).to end_with("engines/billing/config/locales")
    end
  end

  it "evaluates ERB so ENV values resolve" do
    raw = <<~YAML
      defaults:
        provider: <%= ENV.fetch("LL_TEST_PROVIDER", "openai") %>
    YAML
    with_app(locales: {}, raw_config: raw) do |root|
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("LL_TEST_PROVIDER", "openai").and_return("anthropic")
      expect(config_for(root).provider).to eq(:anthropic)
    end
  end

  it "raises for an unknown package" do
    with_app(locales: {}, config: {}) do |root|
      expect { config_for(root, package: "nope").target_locales }
        .to raise_error(Locallingo::Error, /No package/)
    end
  end

  describe "#language_guide" do
    it "reads inline guidance text" do
      raw = <<~YAML
        defaults:
          language_guides:
            de: "Use formal Sie."
      YAML
      with_app(locales: {}, raw_config: raw) do |root|
        expect(config_for(root).language_guide("de")).to eq("Use formal Sie.")
      end
    end

    it "reads guidance from a file: path relative to base_path" do
      with_app(locales: {}, raw_config: "defaults:\n  language_guides:\n    de:\n      file: guides/de.md\n") do |root|
        FileUtils.mkdir_p(File.join(root, "guides"))
        File.write(File.join(root, "guides", "de.md"), "German rules here")
        expect(config_for(root).language_guide("de")).to eq("German rules here")
      end
    end
  end

  describe "#quality_sample_size" do
    it "defaults to 100" do
      with_app(locales: {}, config: {}) do |root|
        expect(config_for(root).quality_sample_size).to eq(100)
      end
    end

    it "reads quality.sample_size" do
      with_app(locales: {}, config: { "quality" => { "sample_size" => 250 } }) do |root|
        expect(config_for(root).quality_sample_size).to eq(250)
      end
    end
  end

  describe "#strict_types" do
    it "returns the configured symbols per tier" do
      with_app(locales: {}, config: {}) do |root|
        config = config_for(root)
        expect(config.strict_types(:strict)).to eq(%i[missing outdated])
        expect(config.strict_types(:strict_all)).to eq(%i[missing outdated duplicate_value])
      end
    end
  end
end
