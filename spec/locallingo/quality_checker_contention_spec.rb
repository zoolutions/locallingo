# frozen_string_literal: true

# One QualityChecker shared by many threads, and by many fibers in one Async
# reactor (#35): every call reads the same locale file and must return the
# same suggestions.
RSpec.describe Locallingo::QualityChecker do
  let(:root) { Dir.mktmpdir("locallingo") }
  let(:texts) do
    { "hi" => "Sorry, you can not pick a color here", "bye" => "Click here for the wire transfer asap" }
  end
  # Built here, on the example's thread, then shared by every caller.
  let(:subject_call) do
    checker = described_class.new(config: config_for(root))
    -> { checker.check(locale: "en") }
  end

  before do
    locales_dir = File.join(root, "config", "locales")
    FileUtils.mkdir_p(locales_dir)
    File.write(File.join(locales_dir, "greeting.en.yml"), { "en" => { "greeting" => texts } }.to_yaml)
    write_config(root, { "quality" => { "british_spellings" => true, "terminology" => "banking" } }, nil)
  end

  after { FileUtils.remove_entry(root) }

  it "finds the suggestions the contention examples compare" do
    categories = subject_call.call.map { |suggestion| suggestion[:category] }

    expect(categories).to include(:grammar, :business, :british_spelling, :terminology)
  end

  it_behaves_like "thread-safe under contention", threads: 8, iterations: 25, consistent: :equal
  it_behaves_like "fiber-safe under an Async reactor", fibers: 8, iterations: 25, consistent: :equal
end
