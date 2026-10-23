# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::QualityChecker do
  def checker_for(root, **kwargs)
    described_class.new(config: config_for(root), **kwargs)
  end

  describe "#check static rules" do
    it "flags 'click here' and vague words" do
      with_app(locales: { "en" => { "ui" => { "link" => "Click here to continue",
                                              "note" => "and other stuff" } } }) do |root|
        suggestions = checker_for(root).check(locale: "en")
        issues = suggestions.map { |s| s[:issue] }
        expect(issues).to include(a_string_matching(/click here/i))
        expect(issues).to include(a_string_matching(/stuff/i))
      end
    end

    it "reports a universal fix for 'can not' with a case-preserving fix payload" do
      with_app(locales: { "en" => { "ui" => { "msg" => "You can not do that" } } }) do |root|
        suggestions = checker_for(root).check(locale: "en")
        fix = suggestions.find { |s| s[:fix] }
        expect(fix[:fix]).to eq(from: "can not", to: "cannot")
      end
    end
  end

  describe "British spellings" do
    it "is off by default" do
      with_app(locales: { "en" => { "ui" => { "t" => "Organization center" } } }) do |root|
        suggestions = checker_for(root).check(locale: "en")
        expect(suggestions.select { |s| s[:category] == :british_spelling }).to be_empty
      end
    end

    it "flags American spellings when enabled, source locale only" do
      with_app(
        config: { "quality" => { "british_spellings" => true } },
        locales: { "en" => { "ui" => { "t" => "Organization center" } } }
      ) do |root|
        suggestions = checker_for(root).check(locale: "en")
        matches = suggestions.select { |s| s[:category] == :british_spelling }.map { |s| s[:match] }
        expect(matches).to include("organization", "center")
      end
    end
  end

  describe "terminology" do
    it "uses the banking list when configured, flagging 'wire transfer'" do
      with_app(
        config: { "quality" => { "terminology" => "banking" } },
        locales: { "en" => { "ui" => { "t" => "Send a wire transfer" } } }
      ) do |root|
        issues = checker_for(root).check(locale: "en").filter_map { |s| s[:issue] }
        expect(issues).to include(a_string_matching(/bank transfer/i))
      end
    end
  end

  describe "#fix!" do
    it "rewrites fixable suggestions in the locale file, preserving case" do
      with_app(locales: { "en" => { "ui" => { "a" => "You can not go", "b" => "Can not stop" } } }) do |root|
        result = checker_for(root).fix!(locale: "en")
        expect(result[:fixed]).to eq(1)

        content = File.read(File.join(root, "config/locales/ui.en.yml"))
        expect(content).to include("You cannot go")
        expect(content).to include("Cannot stop")
      end
    end

    it "does not write when dry_run is true" do
      with_app(locales: { "en" => { "ui" => { "a" => "You can not go" } } }) do |root|
        before = File.read(File.join(root, "config/locales/ui.en.yml"))
        checker_for(root).fix!(locale: "en", dry_run: true)
        expect(File.read(File.join(root, "config/locales/ui.en.yml"))).to eq(before)
      end
    end
  end

  describe "AI suggestions" do
    it "returns [] and warns when credentials are missing" do
      with_app(locales: { "en" => { "ui" => { "a" => "Hi" } } }) do |root|
        stub_llm_missing_credentials
        checker = checker_for(root)
        expect(checker.suggest_improvements({ "ui.a" => "Hi" }, "en")).to eq([])
      end
    end

    it "maps provider output into suggestion hashes when credentials present" do
      with_app(locales: { "en" => { "ui" => { "a" => "Hi" } } }) do |root|
        stub_llm_chat do |**|
          { "ui.a" => { "issue" => "too terse", "suggestion" => "Hello", "severity" => "warning" } }
        end
        result = checker_for(root).suggest_improvements({ "ui.a" => "Hi" }, "en")
        expect(result.first).to include(key: "ui.a", source: :ai, severity: :warning, issue: "too terse")
      end
    end

    it "includes the locale's language guide in the AI review prompt" do
      with_app(
        config: { "language_guides" => { "de" => "Use du-form for yoga.*, Sie-form elsewhere." } },
        locales: { "de" => { "yoga" => { "a" => "Atme ein" } } }
      ) do |root|
        prompts = []
        stub_llm_chat do |instructions:, **|
          prompts << instructions
          {}
        end
        checker_for(root).check(locale: "de", use_ai: true)
        expect(prompts.first).to include("Use du-form for yoga.*, Sie-form elsewhere.")
      end
    end

    it "omits other locales' language guides from the AI review prompt" do
      with_app(
        config: { "language_guides" => { "sv" => "Swedish-only rule" } },
        locales: { "de" => { "yoga" => { "a" => "Atme ein" } } }
      ) do |root|
        prompts = []
        stub_llm_chat do |instructions:, **|
          prompts << instructions
          {}
        end
        checker_for(root).check(locale: "de", use_ai: true)
        expect(prompts.first).not_to include("Swedish-only rule")
      end
    end

    it "samples at most quality.sample_size keys" do
      keys = (1..5).to_h { |i| ["k#{i}", "Text #{i}"] }
      with_app(config: { "quality" => { "sample_size" => 2 } }, locales: { "en" => { "ui" => keys } }) do |root|
        payloads = []
        stub_llm_chat do |payload:, **|
          payloads << payload
          {}
        end
        checker_for(root).check(locale: "en", use_ai: true)
        expect(payloads.first.size).to eq(2)
      end
    end
  end

  describe "#check with keys:" do
    it "sends every named key to the AI pass, unsampled" do
      keys = (1..5).to_h { |i| ["k#{i}", "Text #{i}"] }
      with_app(config: { "quality" => { "sample_size" => 1 } }, locales: { "en" => { "ui" => keys } }) do |root|
        payloads = []
        stub_llm_chat do |payload:, **|
          payloads << payload
          {}
        end
        checker_for(root).check(locale: "en", use_ai: true, keys: %w[ui.k1 ui.k3 ui.k5])
        expect(payloads.first.keys).to eq(%w[ui.k1 ui.k3 ui.k5])
      end
    end
  end

  describe "#check with prefix:" do
    let(:locales) do
      { "en" => { "yoga" => { "a" => "Click here to breathe", "b" => "Stretch" },
                  "ui" => { "c" => "Click here to continue" } } }
    end

    it "scopes the static checks to keys under the prefix" do
      with_app(locales:) do |root|
        keys = checker_for(root).check(locale: "en", prefix: "yoga.").map { |s| s[:key] }
        expect(keys).to include("yoga.a")
        expect(keys).not_to include("ui.c")
      end
    end

    it "sends only keys under the prefix to the AI pass" do
      with_app(locales:) do |root|
        payloads = []
        stub_llm_chat do |payload:, **|
          payloads << payload
          {}
        end
        checker_for(root).check(locale: "en", use_ai: true, prefix: "yoga.")
        expect(payloads.first.keys).to contain_exactly("yoga.a", "yoga.b")
      end
    end

    it "raises when no key matches the prefix" do
      with_app(locales:) do |root|
        expect { checker_for(root).check(locale: "en", prefix: "nope.") }
          .to raise_error(Locallingo::Error, /No keys match prefix "nope\." in en/)
      end
    end
  end

  describe "#check_texts" do
    def bare_checker(**kwargs)
      Dir.mktmpdir do |root|
        yield described_class.new(config: Locallingo::Configuration.load(root_path: root), **kwargs), root
      end
    end

    it "returns the static findings for a hash without reading any locale file" do
      bare_checker do |checker, root|
        expect(Dir.exist?(File.join(root, "config/locales"))).to be(false)
        allow(YAML).to receive(:load_file).and_call_original

        suggestions = checker.check_texts({ "a" => "Click here to continue", b: "You can not do that" }, locale: "en")

        expect(suggestions.map { |s| s[:key] }).to include("a", "b")
        expect(suggestions.find { |s| s[:fix] }).to include(key: "b", fix: { from: "can not", to: "cannot" })
        expect(suggestions.map { |s| s[:source] }.uniq).to eq([:static])
        expect(YAML).not_to have_received(:load_file)
      end
    end

    it "sends every given key to the AI pass, unsampled" do
      payloads = []
      stub_llm_chat do |payload:, **|
        payloads << payload
        { "k2" => { "issue" => "stiff", "suggestion" => "Hallo", "severity" => "warning" } }
      end
      texts = (1..5).to_h { |i| ["k#{i}", "Text #{i}"] }

      bare_checker do |checker|
        allow(checker.config).to receive(:quality_sample_size).and_return(1)
        suggestions = checker.check_texts(texts, locale: "de", use_ai: true)

        expect(payloads).to eq([texts])
        expect(suggestions.last).to include(key: "k2", source: :ai, severity: :warning, locale: "de")
      end
    end

    it "makes no AI call for an empty hash" do
      payloads = []
      stub_llm_chat do |payload:, **|
        payloads << payload
        {}
      end

      bare_checker { |checker| expect(checker.check_texts({}, locale: "en", use_ai: true)).to eq([]) }
      expect(payloads).to be_empty
    end

    it "is what #check and #check_key return for the same texts" do
      locales = { "en" => { "ui" => { "link" => "Click here to continue", "msg" => "You can not do that" } } }
      with_app(locales:) do |root|
        checker = checker_for(root)
        texts = { "ui.link" => "Click here to continue", "ui.msg" => "You can not do that" }

        expect(checker.check(locale: "en")).to eq(checker.check_texts(texts, locale: "en"))
        expect(checker.check_key("ui.msg", "en")).to eq(checker.check_texts(texts.slice("ui.msg"), locale: "en"))
        expect(checker.check_key("ui.nope", "en")).to eq([{ key: "ui.nope", error: "Key not found" }])
      end
    end
  end

  describe "context:" do
    it "runs the AI pass on the given RubyLLM context" do
      require "ruby_llm"
      context = RubyLLM.context { |c| c.openai_api_key = "tenant-key" }
      conversation = double
      allow(conversation).to receive_messages(with_instructions: conversation, ask: double(content: "{}"))
      allow(context).to receive(:chat).and_return(conversation)

      Dir.mktmpdir do |root|
        checker = described_class.new(config: Locallingo::Configuration.load(root_path: root), context:)
        checker.check_texts({ "a" => "Hallo" }, locale: "de", use_ai: true)
      end

      expect(context).to have_received(:chat)
    end
  end
end
