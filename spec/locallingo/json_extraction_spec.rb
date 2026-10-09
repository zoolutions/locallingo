# frozen_string_literal: true

require "spec_helper"

RSpec.describe Locallingo::JsonExtraction do
  describe ".extract_object" do
    it "parses a bare JSON object" do
      expect(described_class.extract_object('{"a":"1","b":"2"}')).to eq("a" => "1", "b" => "2")
    end

    it "recovers an object from a ```json fenced block" do
      content = "Here you go:\n```json\n{\"key\": \"value\"}\n```\nDone."
      expect(described_class.extract_object(content)).to eq("key" => "value")
    end

    it "recovers an object wrapped in prose" do
      content = 'Sure! {"greeting.hi": "Hallo"} is the translation.'
      expect(described_class.extract_object(content)).to eq("greeting.hi" => "Hallo")
    end

    it "ignores a stray %{placeholder} brace before the real object" do
      content = 'Preserved %{name} then: {"msg": "Hei %{name}"}'
      expect(described_class.extract_object(content)).to eq("msg" => "Hei %{name}")
    end

    it "raises for a top-level array" do
      expect { described_class.extract_object('["a","b"]') }
        .to raise_error(JSON::ParserError, /top-level JSON object/)
    end

    it "names the parse error inside a complete fence, not the fence itself" do
      content = <<~TEXT
        ```json
        {
          "app.greeting": "Hallo",
          "app.quoted": ""%{name}" ist der Liste beigetreten"
        }
        ```
      TEXT

      expect { described_class.extract_object(content) }.to raise_error(JSON::ParserError) { |error|
        expect(error.message).to include("%{name}")
        expect(error.message).to include("inside the fenced block")
        expect(error.message).not_to include("```")
      }
    end

    it "raises when no JSON object can be recovered" do
      expect { described_class.extract_object("no json here at all") }
        .to raise_error(JSON::ParserError)
    end
  end
end
