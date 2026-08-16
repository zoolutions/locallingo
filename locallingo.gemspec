# frozen_string_literal: true

require_relative "lib/locallingo/version"

Gem::Specification.new do |s|
  s.name = "locallingo"
  s.version = Locallingo::VERSION
  s.licenses = ["MIT"]
  s.summary = "AI-assisted i18n translation, drift detection, and quality linting on top of i18n-tasks"
  s.description = "Locallingo extends i18n-tasks with AI translation (via RubyLLM — OpenAI, Anthropic, " \
                  "and more), source-hash drift detection so only missing/changed keys are re-translated, " \
                  "and a static + AI translation-quality linter. Everything app-specific — target locales, " \
                  "provider/model, prompt context and glossary, per-language style guides, which validators " \
                  "and quality rules run, and post-translate hooks — is config-driven via `.locallingo.yml`, " \
                  "with a default block plus optional per-package overrides. Ships the `lingo` CLI."
  s.authors = ["Mikael Henriksson"]
  s.email = "mikael@zoolutions.llc"

  # Use `git ls-files` when packaging from a checkout; fall back to a Dir glob
  # when there is no .git (e.g. building from a source copy).
  s.files = begin
    files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
      ls.readlines("\x0", chomp: true).select do |f|
        f.start_with?("exe/", "lib/", "config/") ||
          f == "CHANGELOG.md" || f == "LICENSE.txt" || f == "README.md"
      end
    end
    files.empty? ? raise(Errno::ENOENT) : files
  rescue Errno::ENOENT
    Dir[
      "exe/*", "lib/**/*", "config/**/*",
      "CHANGELOG.md", "LICENSE.txt", "README.md"
    ].select { |f| File.file?(f) }
  end

  s.bindir = "exe"
  s.executables = s.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  s.homepage = "https://github.com/zoolutions/locallingo"
  s.metadata = {
    "source_code_uri" => "https://github.com/zoolutions/locallingo",
    "changelog_uri" => "https://github.com/zoolutions/locallingo/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/zoolutions/locallingo/issues",
    "rubygems_mfa_required" => "true"
  }

  s.required_ruby_version = ">= 3.2"

  # Provider-agnostic LLM client — routes translation and quality-review calls to
  # OpenAI/Anthropic/Google/... chosen by `.locallingo.yml`.
  s.add_dependency "ruby_llm", ">= 1.0", "< 2"
  # Flat YAML locale IO is done by the gem itself; i18n-tasks is invoked (via the
  # `after_translate` hooks) for normalization, so it is NOT a hard runtime dep —
  # the host app already carries it. Left out on purpose.

  # RuboCop is a DEVELOPMENT-time dependency. Locallingo ships i18n cops under
  # lib/rubocop/cop/locallingo/, but `require "locallingo/rubocop"` loads rubocop
  # lazily, so it is never pulled into a host app's runtime — the app already has
  # rubocop in its own Gemfile, and that is what runs the shipped cops. Pinned
  # here so the gem's own cop specs can run.
  s.add_development_dependency "rubocop", ">= 1.75", "< 2"
end
