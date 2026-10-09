# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::CLI do
  # Run the CLI inside a tmp app, capturing stdout/stderr and the exit code.
  def run_cli(root, argv)
    out = StringIO.new
    err = StringIO.new
    code = 0
    Dir.chdir(root) do
      original_out = $stdout
      original_err = $stderr
      $stdout = out
      $stderr = err
      begin
        described_class.start(argv)
      rescue SystemExit => e
        code = e.status
      ensure
        $stdout = original_out
        $stderr = original_err
      end
    end
    [out.string, err.string, code]
  end

  let(:locales) do
    {
      "en" => { "greeting" => { "hi" => "Hello", "bye" => "Goodbye" } },
      "de" => { "greeting" => { "hi" => "Hallo" } }
    }
  end

  describe "translate" do
    before { stub_const("Locallingo::BatchTranslator::BASE_SLEEP_DURATION", 0) }

    it "prints success and exits 0 when every key is translated" do
      with_app(config: { "target_locales" => %w[de], "after_translate" => [] }, locales:) do |root|
        stub_llm_chat { |payload:, **| payload.transform_values { |v| "DE:#{v}" } }

        out, _err, code = run_cli(root, %w[translate])

        expect(out).to include("✅ Translation complete!")
        expect(code).to eq(0)
      end
    end

    it "prints the failed count, still runs hooks, and exits 1 when keys fail" do
      with_app(config: { "target_locales" => %w[de], "after_translate" => ["touch hook-ran"] }, locales:) do |root|
        stub_llm_chat { |**| raise JSON::ParserError, "unexpected token" }

        out, _err, code = run_cli(root, %w[translate])

        expect(out).to include("⚠️ Translation finished: 1 key failed")
        expect(out).to include("greeting.bye")
        expect(out).not_to include("✅")
        expect(File).to exist(File.join(root, "hook-ran"))
        expect(code).to eq(1)
      end
    end

    it "reports failures but exits 0 on --dry-run" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        stub_llm_chat { |**| raise JSON::ParserError, "unexpected token" }

        out, _err, code = run_cli(root, %w[translate --dry-run])

        expect(out).to include("1 key failed")
        expect(code).to eq(0)
      end
    end
  end

  describe "validate" do
    it "reports missing keys and exits 1 under --strict" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        out, _err, code = run_cli(root, %w[validate --strict])
        expect(out).to include("Translation Issues Found")
        expect(out).to include("greeting.bye")
        expect(code).to eq(1)
      end
    end

    it "exits 0 when there are no violations" do
      full = { "en" => { "greeting" => { "hi" => "Hello" } }, "de" => { "greeting" => { "hi" => "Hallo" } } }
      with_app(config: { "target_locales" => %w[de] }, locales: full) do |root|
        # Sync state so nothing reads as outdated.
        Locallingo::Manager.new(config: config_for(root)).sync_state!
        out, _err, code = run_cli(root, %w[validate --strict])
        expect(out).to include("All translations valid")
        expect(code).to eq(0)
      end
    end
  end

  describe "legacy flag aliases" do
    it "accepts --validate, warns deprecation, and behaves like `validate`" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        out, err, code = run_cli(root, %w[--validate --strict])
        expect(err).to match(/\[deprecated\].*--validate.*use `lingo validate`/)
        expect(out).to include("greeting.bye")
        expect(code).to eq(1)
      end
    end
  end

  describe "status (default command)" do
    it "prints status when no command is given" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        out, _err, _code = run_cli(root, [])
        expect(out).to include("Translation Status")
        expect(out).to include("Missing: 1")
      end
    end
  end

  describe "hash" do
    it "prints the source hash as json with --json" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        out, _err, _code = run_cli(root, %w[hash --json])
        expect(out).to include('"hash":')
      end
    end
  end

  describe "accept-edits" do
    let(:accept_config) do
      { "target_locales" => %w[de], "validators" => { "manual_edits" => true } }
    end
    let(:accept_locales) do
      {
        "en" => { "g" => { "hi" => "Hello", "bye" => "Goodbye" } },
        "de" => { "g" => { "hi" => "Hallo edited", "bye" => "Tschau" } }
      }
    end

    def seed_state(root)
      write_state(root, "g.de.json",
                  "g.hi" => { "source_hash" => Locallingo::StateStore.hash("Hello"),
                              "target_hash" => "00000000" },
                  "g.bye" => { "source_hash" => Locallingo::StateStore.hash("Goodbye"),
                               "target_hash" => Locallingo::StateStore.hash("Tschau") })
    end

    it "unscoped accepts only drifted keys" do
      with_app(config: accept_config, locales: accept_locales) do |root|
        seed_state(root)

        out, _err, _code = run_cli(root, %w[accept-edits])

        state = read_state(root, "g.de.json")
        expect(state.dig("g.hi", "manual")).to be(true)
        expect(state.fetch("g.bye")).not_to have_key("manual")
        expect(out).to include("1")
      end
    end

    it "--key stamps only the named key" do
      with_app(config: accept_config, locales: accept_locales) do |root|
        seed_state(root)

        run_cli(root, %w[accept-edits --locale de --key g.bye])

        state = read_state(root, "g.de.json")
        expect(state.dig("g.bye", "manual")).to be(true)
        expect(state.fetch("g.hi")).not_to have_key("manual")
      end
    end

    it "--all stamps every translated key" do
      with_app(config: accept_config, locales: accept_locales) do |root|
        seed_state(root)

        run_cli(root, %w[accept-edits --all])

        state = read_state(root, "g.de.json")
        expect(state.dig("g.hi", "manual")).to be(true)
        expect(state.dig("g.bye", "manual")).to be(true)
      end
    end

    it "fails loudly for an unknown --key" do
      with_app(config: accept_config, locales: accept_locales) do |root|
        seed_state(root)

        _out, err, code = run_cli(root, %w[accept-edits --key g.nope])

        expect(err).to include("g.nope")
        expect(code).to eq(1)
      end
    end
  end

  describe ".locallingo.rb setup file" do
    it "loads it before dispatch so it can configure credentials" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        File.write(
          File.join(root, ".locallingo.rb"),
          'Locallingo.configure { |c| c.anthropic_api_key = "from-setup" }'
        )

        _out, _err, code = run_cli(root, %w[status])

        expect(code).to eq(0)
        expect(Locallingo.settings.anthropic_api_key).to eq("from-setup")
      end
    end

    it "runs silently without one" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        _out, err, code = run_cli(root, %w[status])
        expect(code).to eq(0)
        expect(err).to be_empty
      end
    end

    it "propagates errors from the setup file instead of swallowing them" do
      with_app(config: { "target_locales" => %w[de] }, locales:) do |root|
        File.write(File.join(root, ".locallingo.rb"), "NoSuchConstant.boom!")

        expect { run_cli(root, %w[status]) }.to raise_error(NameError, /NoSuchConstant/)
      end
    end
  end
end
