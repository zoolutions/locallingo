---
description: "Use when implementing any feature or fixing any bug -- enforces RED-GREEN-REFACTOR: write failing test first, implement minimum code to pass, then refactor."
model: sonnet
---

# TDD Command

Enforce test-driven development methodology with RED -> GREEN -> REFACTOR cycle.

## The TDD Cycle

```text
RED -> GREEN -> REFACTOR -> REPEAT

RED:      Write a failing test (test MUST fail first)
GREEN:    Write MINIMAL code to pass (nothing more)
REFACTOR: Improve code while keeping tests green
REPEAT:   Next feature/scenario
```

## When to Use

- Implementing new features
- Adding new validators or quality rules
- Fixing bugs (write test that reproduces bug FIRST)
- Refactoring existing code
- Modifying Manager workflows (translate, sync, accept-edits)
- Changing StateStore behavior
- Adding CLI commands or flags

## Workflow

### Step 1: Write Failing Tests (RED)

```ruby
# spec/locallingo/example_spec.rb
RSpec.describe Locallingo::NewFeature do
  describe "#check" do
    context "when the key is missing in the target locale" do
      it "reports it" do
        expect(subject.check(source, target)).to include("g.missing")
      end
    end

    context "when the target was hand-edited" do
      it "leaves the manual flag intact" do
        expect(state.dig("g.edited", "manual")).to be(true)
      end
    end
  end
end
```

### Step 2: Run Tests - Verify FAIL

```bash
bundle exec rspec spec/locallingo/example_spec.rb

FAIL - NotImplementedError / Expected behavior not met
```

**Tests MUST fail before implementing.** This confirms:
- Tests are actually running
- Tests are testing the right thing
- Implementation doesn't already exist

### Step 3: Implement Minimal Code (GREEN)

Write the minimum code to make the test pass.

### Step 4: Run Tests - Verify PASS

```bash
bundle exec rspec spec/locallingo/example_spec.rb

N examples, 0 failures
```

### Step 5: Refactor (IMPROVE)

Improve code while keeping tests green:
- Extract methods to reduce complexity
- Improve naming
- Reduce duplication

### Step 6: Run Full Suite

```bash
bundle exec rspec
```

## Coverage Requirements

| Code Type | Minimum Coverage |
|-----------|------------------|
| All code | 80% |
| StateStore | 100% |
| Manager sync / accept-edits paths | 100% |
| Validators | 100% |
| Configuration / Settings | 100% |

## Test Types to Include

### Unit Tests (Configuration, StateStore, KeyFlattener)
- Happy path scenarios
- Edge cases (empty locales, missing namespaces, corrupted state)
- Error conditions (state corruption raises `Locallingo::Error`)

### Workflow Tests (Manager)
- Use the `with_app` / `write_state` / `read_state` fixtures in `spec/support/locale_fixtures.rb`
- Translate / sync / accept-edits round-trips
- Manual-flag preservation across rewrites
- Byte-identical files left untouched (no diff churn)

### Provider Tests
- Mock the RubyLLM provider — specs must NEVER make network calls
- Assert on prompt/payload shape, not provider internals

## Best Practices

**DO:**
- Write the test FIRST, before any implementation
- Run tests and verify they FAIL before implementing
- Write MINIMAL code to make tests pass
- Refactor only after tests are green
- Use `Dir.mktmpdir` / `with_app` for filesystem-touching specs
- Test state-format compatibility explicitly when changing the writer

**DON'T:**
- Write implementation before tests
- Skip running tests after each change
- Write too much code at once
- Ignore failing tests
- Test implementation details (test behavior)
- Skip testing error paths

## Checklist

- [ ] Tests written BEFORE implementation
- [ ] Tests fail initially (RED phase verified)
- [ ] Minimal code written to pass (GREEN)
- [ ] Code refactored with tests still passing
- [ ] Coverage meets requirements (80%+)
- [ ] All edge cases covered
- [ ] Backwards compatibility maintained
