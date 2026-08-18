# Testing Rules

## TDD Workflow

Follow RED -> GREEN -> REFACTOR:

1. **RED**: Write a failing test first
2. **GREEN**: Write minimal code to pass
3. **REFACTOR**: Improve code while keeping tests green

## Coverage Requirements

- **80% minimum** for all code
- **100% required** for:
  - StateStore (drift state — corruption or loss is unrecoverable)
  - Manager sync/accept-edits paths (manual-flag preservation)
  - Validators (missing, outdated, duplicate_values, manual_edits)
  - Configuration / Settings resolution

## Test Type Preference

| Feature involves | Use |
|-----------------|-----|
| Configuration / Settings / KeyFlattener | Unit spec |
| StateStore | Unit spec with `Dir.mktmpdir` |
| Manager workflows | Spec with `with_app` fixture (spec/support/locale_fixtures.rb) |
| LLM translation | Unit spec with mocked provider — NEVER real network calls |
| CLI | Spec on `Locallingo::CLI` argument parsing and dispatch |
| RuboCop cops | `rubocop-rspec` cop specs |

## RSpec Conventions

```ruby
# Use let for setup
let(:config) { Locallingo::Configuration.new }

# Use the shared fixtures for app-shaped tests
it "syncs state" do
  with_app(config: { "target_locales" => %w[de] }, locales: locales) do |root|
    write_state(root, "g.de.json", "g.hi" => { "source_hash" => "..." })
    # ...
  end
end

# Use contexts for scenarios
context "when the state file is corrupted" do
  it { expect { store.load("de") }.to raise_error(Locallingo::Error) }
end
```

## Provider Mocking

- Mock the RubyLLM provider in all specs — no API keys, no network
- Fixture translations are plain hashes; assert on the prompt/payload shape, not provider internals

## Test Checklist

- [ ] Tests written BEFORE implementation
- [ ] All tests pass: `bundle exec rspec`
- [ ] Coverage meets requirements
- [ ] No skipped tests without reason
- [ ] Edge cases covered (corrupted state, empty locales, missing namespaces, hand-edited targets)
- [ ] Error paths tested (state corruption raises, unknown keys raise)
