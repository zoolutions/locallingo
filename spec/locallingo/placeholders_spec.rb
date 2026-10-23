# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::Placeholders do
  let(:liquid) { [/\{\{.*?\}\}/m, /\{%.*?%\}/m] }

  describe ".tokens" do
    it "collects every match of every pattern" do
      text = "{% button url: links.home %}Hi {{ item.name }}{% endbutton %}"

      expect(described_class.tokens(text, liquid))
        .to eq(["{{ item.name }}", "{% button url: links.home %}", "{% endbutton %}"])
    end

    it "collects the whole match when a pattern has capture groups" do
      expect(described_class.tokens("Hi %{name}, %{count}", [/%\{(\w+)\}/])).to eq(["%{name}", "%{count}"])
    end

    it "returns no tokens without patterns" do
      expect(described_class.tokens("Hi {{ name }}", [])).to eq([])
    end
  end

  describe ".compare" do
    let(:source) { "{% paragraph %}Your {{ item.name }} for {{ user.name }}{% endparagraph %}" }

    it "is nil for the same tokens in another order" do
      translated = "{% paragraph %}Für {{ user.name }}: Ihr {{ item.name }}{% endparagraph %}"

      expect(described_class.compare(source, translated, liquid)).to be_nil
    end

    it "reports a dropped token as missing" do
      translated = "Ihr {{ item.name }} für {{ user.name }}{% endparagraph %}"

      expect(described_class.compare(source, translated, liquid))
        .to eq("missing" => ["{% paragraph %}"], "extra" => [])
    end

    it "reports an added token as extra" do
      translated = "{% paragraph %}Ihr {{ item.name }} {{ item.name }} für {{ user.name }}{% endparagraph %}"

      expect(described_class.compare(source, translated, liquid))
        .to eq("missing" => [], "extra" => ["{{ item.name }}"])
    end

    it "reports an altered token as missing and extra" do
      translated = "{% paragraph %}Ihr {{ artikel.name }} für {{ user.name }}{% endparagraph %}"

      expect(described_class.compare(source, translated, liquid))
        .to eq("missing" => ["{{ item.name }}"], "extra" => ["{{ artikel.name }}"])
    end

    it "treats whitespace inside a token as part of it" do
      expect(described_class.compare("Hi {{ name }}", "Hallo {{name}}", liquid))
        .to eq("missing" => ["{{ name }}"], "extra" => ["{{name}}"])
    end

    it "counts repeated tokens" do
      expect(described_class.compare("{{ a }} and {{ a }}", "{{ a }}", liquid))
        .to eq("missing" => ["{{ a }}"], "extra" => [])
    end

    it "is nil without patterns" do
      expect(described_class.compare("{{ a }}", "nothing", [])).to be_nil
    end
  end
end
