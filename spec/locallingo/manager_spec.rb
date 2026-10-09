# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::Manager do
  describe "#validate" do
    it "reports missing target keys" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello", "bye" => "Goodbye" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        violations = described_class.new(config: config_for(root)).validate
        expect(violations).to include(a_hash_including(type: :missing, locale: "de", key: "greeting.bye"))
      end
    end

    context "with the duplicate_values validator enabled" do
      it "reports a view-scoped key duplicating an AR attribute value" do
        with_app(
          config: { "target_locales" => %w[de], "validators" => { "duplicate_values" => true } },
          locales: {
            "en" => {
              "activerecord" => { "attributes" => { "user" => { "name" => "Name" } } },
              "admin" => { "users" => { "index" => { "name_column" => "Name" } } }
            }
          }
        ) do |root|
          violations = described_class.new(config: config_for(root)).validate
          expect(violations).to include(
            a_hash_including(
              type: :duplicate_value,
              locale: "en",
              key: "admin.users.index.name_column",
              suggestion: a_string_including("activerecord.attributes.user.name")
            )
          )
        end
      end

      it "does not flag when no duplication exists" do
        with_app(
          config: { "target_locales" => %w[de], "validators" => { "duplicate_values" => true } },
          locales: {
            "en" => {
              "activerecord" => { "attributes" => { "user" => { "name" => "Name" } } },
              "admin" => { "users" => { "index" => { "title" => "User Index" } } }
            }
          }
        ) do |root|
          violations = described_class.new(config: config_for(root)).validate
          expect(violations.select { |v| v[:type] == :duplicate_value }).to be_empty
        end
      end
    end

    it "does not run duplicate_values when disabled (default)" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => {
            "activerecord" => { "attributes" => { "user" => { "name" => "Name" } } },
            "admin" => { "users" => { "index" => { "name_column" => "Name" } } }
          }
        }
      ) do |root|
        violations = described_class.new(config: config_for(root)).validate
        expect(violations.select { |v| v[:type] == :duplicate_value }).to be_empty
      end
    end
  end

  describe "#status" do
    it "counts missing and outdated keys per locale" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello", "bye" => "Bye" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        status = described_class.new(config: config_for(root)).status
        expect(status["de"]).to include(total_keys: 2, translated: 1, missing: 1)
      end
    end
  end

  describe "#translate!" do
    it "translates missing keys via the provider and writes them to the locale file" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello", "bye" => "Goodbye" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        # payload arrives as { "greeting.bye" => "Goodbye" }
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        config = config_for(root)
        described_class.new(config:).translate!(locale: "de")

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "bye")).to eq("DE:Goodbye")
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo") # untouched
      end
    end

    it "records state so a re-run has nothing to translate" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello" } },
          "de" => {}
        }
      ) do |root|
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }
        config = config_for(root)
        described_class.new(config:).translate!(locale: "de")

        status = described_class.new(config: config_for(root)).status
        expect(status["de"][:missing]).to eq(0)
      end
    end

    it "raises when credentials are missing" do
      with_app(config: { "target_locales" => %w[de] }, locales: { "en" => { "g" => { "h" => "Hi" } } }) do |root|
        stub_llm_missing_credentials
        expect { described_class.new(config: config_for(root)).translate!(locale: "de") }
          .to raise_error(Locallingo::MissingCredentialsError)
      end
    end
  end

  describe "#translate! with unparseable or failing replies" do
    let(:keys) { %w[a b c d e f g h] }
    let(:locales) { { "en" => { "g" => keys.to_h { |k| [k, "Text #{k}"] } } } }

    before { stub_const("Locallingo::BatchTranslator::BASE_SLEEP_DURATION", 0) }

    def de_values(root)
      file = File.join(root, "config/locales/g.de.yml")
      File.exist?(file) ? YAML.load_file(file).dig("de", "g") : {}
    end

    it "fails only the key whose reply cannot be parsed, writes the rest, and returns the failures" do
      with_app(config: { "target_locales" => %w[de], "translate" => { "batch_size" => 20 } }, locales:) do |root|
        calls = []
        stub_llm_chat do |payload:, **|
          calls << payload.keys
          raise JSON::ParserError, "unexpected token" if payload.key?("g.c")

          payload.transform_values { |v| "DE:#{v}" }
        end

        failed = described_class.new(config: config_for(root)).translate!(locale: "de")

        expect(failed).to eq("de" => ["g.c"])
        expect(de_values(root).keys).to match_array(keys - ["c"])
        # 8 → 4 → 2 → 1: one call per level for each half, never the same payload twice.
        expect(calls.size).to eq(7)
        expect(calls.uniq.size).to eq(calls.size)
      end
    end

    it "returns an empty failure list for a locale with nothing to translate" do
      with_app(config: { "target_locales" => %w[de] },
               locales: { "en" => { "g" => { "a" => "A" } }, "de" => { "g" => { "a" => "A-de" } } }) do |root|
        stub_llm_chat { |**| raise "must not be called" }

        expect(described_class.new(config: config_for(root)).translate!).to eq("de" => [])
      end
    end

    it "asks the model to escape double quotes and keep typographic quotes" do
      with_app(config: { "target_locales" => %w[de] }, locales: { "en" => { "g" => { "a" => "A" } } }) do |root|
        prompt = nil
        stub_llm_chat do |payload:, instructions:, **|
          prompt = instructions
          payload.transform_values { |v| "DE:#{v}" }
        end

        described_class.new(config: config_for(root)).translate!(locale: "de")

        expect(prompt).to include('\\"')
        expect(prompt).to include("“ ” „ ‚ « »")
      end
    end
  end

  describe "#translate! prompt" do
    { "de" => "German", "it" => "Italian", "sv" => "Swedish" }.each do |locale, language|
      it "asks for idiomatic #{language} rather than a word-for-word translation" do
        with_app(config: { "target_locales" => [locale] }, locales: { "en" => { "g" => { "a" => "A" } } }) do |root|
          prompt = nil
          stub_llm_chat do |payload:, instructions:, **|
            prompt = instructions
            payload.transform_values { |v| "#{locale}:#{v}" }
          end

          described_class.new(config: config_for(root)).translate!(locale:)

          expect(prompt).to include("from English into natural, idiomatic #{language}")
          expect(prompt).to include("native #{language} speaker")
          expect(prompt).to include("not word for word")
          expect(prompt).to include("Avoid calques")
          expect(prompt).to include("Never add, drop or change information")
          expect(prompt).to include("Terminology and any language guide below take precedence")
          expect(prompt).not_to include("formal business language")
        end
      end
    end
  end

  describe "#source_hash" do
    it "is stable across calls and changes when source changes" do
      with_app(config: {}, locales: { "en" => { "g" => { "h" => "Hi" } } }) do |root|
        first = described_class.new(config: config_for(root)).source_hash
        again = described_class.new(config: config_for(root)).source_hash
        expect(first).to eq(again)

        File.write(
          File.join(root, "config/locales/g.en.yml"),
          { "en" => { "g" => { "h" => "Changed" } } }.to_yaml
        )
        expect(described_class.new(config: config_for(root)).source_hash).not_to eq(first)
      end
    end
  end

  describe "#sync_state! state preservation" do
    it "preserves target_hash and manual while refreshing source_hash" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        write_state(root, "greeting.de.json",
                    "greeting.hi" => {
                      "source_hash" => "stale000", "target_hash" => "cafecafe", "manual" => true
                    })

        described_class.new(config: config_for(root)).sync_state!

        entry = read_state(root, "greeting.de.json").fetch("greeting.hi")
        expect(entry["source_hash"]).to eq(Locallingo::StateStore.hash("Hello"))
        expect(entry["target_hash"]).to eq("cafecafe") # untouched, not recomputed
        expect(entry["manual"]).to be(true)
      end
    end

    it "backfills a missing target_hash from the current value without inventing manual" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => { "source_hash" => "stale000" })

        described_class.new(config: config_for(root)).sync_state!

        entry = read_state(root, "greeting.de.json").fetch("greeting.hi")
        expect(entry).to eq(
          "source_hash" => Locallingo::StateStore.hash("Hello"),
          "target_hash" => Locallingo::StateStore.hash("Hallo")
        )
      end
    end

    it "records a full entry for keys with no state at all" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        described_class.new(config: config_for(root)).sync_state!

        entry = read_state(root, "greeting.de.json").fetch("greeting.hi")
        expect(entry).to eq(
          "source_hash" => Locallingo::StateStore.hash("Hello"),
          "target_hash" => Locallingo::StateStore.hash("Hallo")
        )
      end
    end

    it "still prunes entries for keys no longer in the target files" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        write_state(root, "greeting.de.json",
                    "greeting.hi" => { "source_hash" => "stale000" },
                    "greeting.gone" => { "source_hash" => "dead0000", "manual" => true })

        described_class.new(config: config_for(root)).sync_state!

        expect(read_state(root, "greeting.de.json").keys).to eq(["greeting.hi"])
      end
    end
  end

  describe "#translate! and manual keys" do
    let(:manual_locales) do
      {
        "en" => { "greeting" => { "hi" => "Hello", "bye" => "Goodbye" } },
        "de" => { "greeting" => { "hi" => "Hallo", "bye" => "Tschau" } }
      }
    end
    let(:manual_state) do
      {
        "source_hash" => "stale000",
        "target_hash" => Locallingo::StateStore.hash("Hallo"),
        "manual" => true
      }
    end

    it "skips a manual key named via force_keys and warns about --include-manual" do
      with_app(config: { "target_locales" => %w[de] }, locales: manual_locales) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        expect do
          described_class.new(config: config_for(root)).translate!(locale: "de", force_keys: ["greeting.hi"])
        end.to output(/greeting\.hi.*--include-manual/m).to_stderr

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo")
        expect(read_state(root, "greeting.de.json").fetch("greeting.hi")).to eq(manual_state)
      end
    end

    it "reports 'would skip' and writes nothing on a dry run" do
      with_app(config: { "target_locales" => %w[de] }, locales: manual_locales) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        expect do
          described_class.new(config: config_for(root), dry_run: true)
                         .translate!(locale: "de", force_keys: ["greeting.hi"])
        end.to output(/would skip manual \(hand-edited\) key greeting\.hi/).to_stderr

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo")
        expect(read_state(root, "greeting.de.json").fetch("greeting.hi")).to eq(manual_state)
      end
    end

    it "reports 'would overwrite' under include_manual on a dry run" do
      with_app(config: { "target_locales" => %w[de] }, locales: manual_locales) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        expect do
          described_class.new(config: config_for(root), dry_run: true)
                         .translate!(locale: "de", force_keys: ["greeting.hi"], include_manual: true)
        end.to output(/would overwrite manual \(hand-edited\) key greeting\.hi/).to_stderr

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo")
      end
    end

    it "translates nothing else when every named force_key is manual" do
      locales = manual_locales.merge("en" => { "greeting" => { "hi" => "Hello", "bye" => "Goodbye", "new" => "New" } })
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        payloads = []
        stub_llm_chat do |payload:, **|
          payloads << payload
          payload.transform_values { |v| "DE:#{v}" }
        end

        expect do
          described_class.new(config: config_for(root)).translate!(locale: "de", force_keys: ["greeting.hi"])
        end.to output(/greeting\.hi/).to_stderr

        expect(payloads).to be_empty
        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting")).not_to have_key("new")
      end
    end

    it "still translates a non-manual force_key named alongside a manual one" do
      with_app(config: { "target_locales" => %w[de] }, locales: manual_locales) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        expect do
          described_class.new(config: config_for(root))
                         .translate!(locale: "de", force_keys: %w[greeting.hi greeting.bye])
        end.to output(/greeting\.hi/).to_stderr

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo")
        expect(de.dig("de", "greeting", "bye")).to eq("DE:Goodbye")
      end
    end

    it "retranslates a manual force_key with include_manual, keeping the manual flag and warning" do
      with_app(config: { "target_locales" => %w[de] }, locales: manual_locales) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        expect do
          described_class.new(config: config_for(root))
                         .translate!(locale: "de", force_keys: ["greeting.hi"], include_manual: true)
        end.to output(/overwr.*greeting\.hi/mi).to_stderr

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("DE:Hello")

        entry = read_state(root, "greeting.de.json").fetch("greeting.hi")
        expect(entry["source_hash"]).to eq(Locallingo::StateStore.hash("Hello"))
        expect(entry["target_hash"]).to eq(Locallingo::StateStore.hash("DE:Hello"))
        expect(entry["manual"]).to be(true)
      end
    end

    it "does not let include_manual leak into --force" do
      with_app(config: { "target_locales" => %w[de] }, locales: manual_locales) do |root|
        write_state(root, "greeting.de.json", "greeting.hi" => manual_state)
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        described_class.new(config: config_for(root)).translate!(locale: "de", force: true, include_manual: true)

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo")
      end
    end

    it "skips manual keys under --force" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello", "bye" => "Goodbye" } },
          "de" => { "greeting" => { "hi" => "Hallo", "bye" => "Tschau" } }
        }
      ) do |root|
        write_state(root, "greeting.de.json",
                    "greeting.hi" => {
                      "source_hash" => Locallingo::StateStore.hash("Hello"),
                      "target_hash" => Locallingo::StateStore.hash("Hallo"),
                      "manual" => true
                    })
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        described_class.new(config: config_for(root)).translate!(locale: "de", force: true)

        de = YAML.load_file(File.join(root, "config/locales/greeting.de.yml"))
        expect(de.dig("de", "greeting", "hi")).to eq("Hallo") # protected
        expect(de.dig("de", "greeting", "bye")).to eq("DE:Goodbye")
        expect(read_state(root, "greeting.de.json").dig("greeting.hi", "manual")).to be(true)
      end
    end
  end

  describe "#accept_edits!" do
    let(:matrix_locales) do
      {
        "en" => { "g" => { "machine" => "M", "edited" => "E", "bare" => "B", "fresh" => "F" } },
        "de" => { "g" => { "machine" => "M-de", "edited" => "E-de", "bare" => "B-de", "fresh" => "F-de" } }
      }
    end

    def seed_matrix_state(root)
      write_state(root, "g.de.json",
                  "g.machine" => {
                    "source_hash" => Locallingo::StateStore.hash("M"),
                    "target_hash" => Locallingo::StateStore.hash("M-de")
                  },
                  "g.edited" => {
                    "source_hash" => Locallingo::StateStore.hash("E"),
                    "target_hash" => "00000000"
                  },
                  "g.bare" => { "source_hash" => Locallingo::StateStore.hash("B") })
    end

    it "unscoped accepts only hand-edited (drifted) keys" do
      with_app(config: { "target_locales" => %w[de] }, locales: matrix_locales) do |root|
        seed_matrix_state(root)

        described_class.new(config: config_for(root)).accept_edits!

        state = read_state(root, "g.de.json")
        expect(state.dig("g.edited", "manual")).to be(true)
        expect(state.dig("g.edited", "target_hash")).to eq(Locallingo::StateStore.hash("E-de"))
        expect(state.fetch("g.machine")).not_to have_key("manual")
        expect(state.fetch("g.bare")).to eq("source_hash" => Locallingo::StateStore.hash("B"))
        expect(state).not_to have_key("g.fresh")
      end
    end

    it "with keys: stamps exactly the named keys and leaves other namespaces byte-identical" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "g" => { "hi" => "Hello" }, "admin" => { "title" => "Admin" } },
          "de" => { "g" => { "hi" => "Hallo-edited" }, "admin" => { "title" => "Verwaltung" } }
        }
      ) do |root|
        write_state(root, "g.de.json",
                    "g.hi" => { "source_hash" => Locallingo::StateStore.hash("Hello"),
                                "target_hash" => "deadbeef" })
        write_state(root, "admin.de.json",
                    "admin.title" => { "source_hash" => Locallingo::StateStore.hash("Admin"),
                                       "target_hash" => "cafebabe" })
        admin_before = File.read(File.join(root, ".i18n-state", "admin.de.json"))

        described_class.new(config: config_for(root)).accept_edits!(keys: ["g.hi"])

        expect(read_state(root, "g.de.json").fetch("g.hi")).to eq(
          "source_hash" => Locallingo::StateStore.hash("Hello"),
          "target_hash" => Locallingo::StateStore.hash("Hallo-edited"),
          "manual" => true
        )
        expect(File.read(File.join(root, ".i18n-state", "admin.de.json"))).to eq(admin_before)
      end
    end

    it "with keys: raises for a key present in no locale" do
      with_app(config: { "target_locales" => %w[de] }, locales: matrix_locales) do |root|
        seed_matrix_state(root)

        expect { described_class.new(config: config_for(root)).accept_edits!(keys: ["g.nope"]) }
          .to raise_error(Locallingo::Error, /g\.nope/)
      end
    end

    it "with all: true stamps every translated key" do
      with_app(config: { "target_locales" => %w[de] }, locales: matrix_locales) do |root|
        seed_matrix_state(root)

        described_class.new(config: config_for(root)).accept_edits!(all: true)

        state = read_state(root, "g.de.json")
        expect(state.keys).to match_array(%w[g.machine g.edited g.bare g.fresh])
        expect(state.values).to all(include("manual" => true))
      end
    end
  end

  describe "validator suggestions" do
    it "tells the operator to hand-update outdated manual keys instead of force-translating" do
      with_app(
        config: { "target_locales" => %w[de], "validators" => { "manual_edits" => true } },
        locales: {
          "en" => { "g" => { "hi" => "Hello" } },
          "de" => { "g" => { "hi" => "Hallo" } }
        }
      ) do |root|
        write_state(root, "g.de.json",
                    "g.hi" => {
                      "source_hash" => "stale000",
                      "target_hash" => Locallingo::StateStore.hash("Hallo"),
                      "manual" => true
                    })

        violations = described_class.new(config: config_for(root)).validate
        outdated = violations.find { |v| v[:type] == :outdated }
        expect(outdated[:suggestion]).to include("by hand")
        expect(outdated[:suggestion]).to include("accept-edits --locale de --key g.hi")
      end
    end

    it "keeps the force-key suggestion for outdated non-manual keys" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "g" => { "hi" => "Hello" } },
          "de" => { "g" => { "hi" => "Hallo" } }
        }
      ) do |root|
        write_state(root, "g.de.json", "g.hi" => { "source_hash" => "stale000" })

        violations = described_class.new(config: config_for(root)).validate
        outdated = violations.find { |v| v[:type] == :outdated }
        expect(outdated[:suggestion]).to include("translate --locale de --force-key g.hi")
      end
    end

    it "suggests a key-scoped accept-edits for hand-edited values" do
      with_app(
        config: { "target_locales" => %w[de], "validators" => { "manual_edits" => true } },
        locales: {
          "en" => { "g" => { "hi" => "Hello" } },
          "de" => { "g" => { "hi" => "Hallo edited" } }
        }
      ) do |root|
        write_state(root, "g.de.json",
                    "g.hi" => {
                      "source_hash" => Locallingo::StateStore.hash("Hello"),
                      "target_hash" => "00000000"
                    })

        violations = described_class.new(config: config_for(root)).validate
        manual_edit = violations.find { |v| v[:type] == :manual_edit }
        expect(manual_edit[:suggestion]).to include("accept-edits --locale de --key g.hi")
      end
    end
  end

  describe "#sync_state! then outdated detection" do
    it "flags a key as outdated after its source changes" do
      with_app(
        config: { "target_locales" => %w[de] },
        locales: {
          "en" => { "greeting" => { "hi" => "Hello" } },
          "de" => { "greeting" => { "hi" => "Hallo" } }
        }
      ) do |root|
        config = config_for(root)
        described_class.new(config:).sync_state!

        # Change the English source after state was recorded.
        File.write(
          File.join(root, "config/locales/greeting.en.yml"),
          { "en" => { "greeting" => { "hi" => "Hi there" } } }.to_yaml
        )

        violations = described_class.new(config: config_for(root)).validate
        expect(violations).to include(a_hash_including(type: :outdated, locale: "de", key: "greeting.hi"))
      end
    end
  end
end
