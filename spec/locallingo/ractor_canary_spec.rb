# frozen_string_literal: true

# The pure core, run inside a non-main Ractor (Ruby 4.0+; the kit skips these
# with a reason below that): the static quality checks on literal strings, the
# drift decisions over literal state entries, and configuration parsed from a
# literal YAML string. No app files, no LLM (#35). `conformance-kit check` runs
# them with `--tag ractor`.
#
# Each block is capture-free: values come in through inputs:, everything else
# through constants.
RSpec.describe Locallingo do # rubocop:disable RSpec/SpecFilePathFormat -- spans the pure core, not one class
  context "with the static quality checks" do
    let(:subject_call) do
      lambda do |text|
        [
          Locallingo::Quality::StaticRules.check("k", text, "en"),
          Locallingo::Quality::StaticRules.universal_fixes("k", text, "en"),
          Locallingo::Quality::Terminology.new("banking").check("k", text, "en"),
          Locallingo::Quality::Terminology.new(nil).check("k", text, "en"),
          Locallingo::Quality::BritishSpellings.check("k", text, "en")
        ]
      end
    end

    it_behaves_like "runs inside a non-main Ractor",
                    inputs: ["Sorry, you can not pick a color for the wire transfer: click here asap."]
  end

  context "with drift decisions over literal state" do
    let(:subject_call) do
      lambda do |source, target, entry|
        drift = Locallingo::Drift.new
        [
          Locallingo::StateStore.hash(source.fetch("title")),
          drift.digest(source),
          drift.status(source:, target:, entry:),
          drift.due?(source:, target:, entry:),
          drift.hand_edited?(target:, entry:),
          drift.record(source:, target:, manual: true)
        ]
      end
    end

    it_behaves_like "runs inside a non-main Ractor",
                    inputs: [
                      { "title" => "Hello", "steps" => [{ "text" => "Open the app" }] },
                      { "title" => "Hallo", "steps" => [{ "text" => "Öffne die App" }] },
                      { "source_hash" => "00000000", "target_hash" => "ffffffff" }
                    ]
  end

  context "with configuration parsed from a literal YAML string" do
    let(:subject_call) do
      lambda do |yaml|
        [nil, "engines/billing"].map do |package|
          config = Locallingo::Configuration.parse(yaml, root_path: "/app", package:)
          [config.data, config.provider, config.target_locales, config.locales_dir, config.strict_types(:strict)]
        end
      end
    end

    it_behaves_like "runs inside a non-main Ractor", inputs: [<<~YAML]
      defaults:
        target_locales: [de, sv]
        provider: <%= "anthropic" %>
        glossary:
          entity: "business account holder"
      packages:
        - path: engines/billing
          target_locales: [de]
    YAML
  end
end
