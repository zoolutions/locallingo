# Coding Style Rules

## File Organization

**MANY SMALL FILES > FEW LARGE FILES**

- High cohesion, low coupling
- 200-400 lines typical
- 800 lines maximum per file
- Extract complex logic to dedicated classes
- Organize by concern (cli, manager, state, providers, validators, quality)

## Ruby Style

### Classes & Methods

```ruby
# Good: Small, focused methods
def translate!(locale: nil, force: false, force_keys: [])
  each_target_locale(locale) do |target|
    translate_locale(source, target, force:, force_keys:)
  end
end

# Bad: Giant methods doing everything
def process_everything
  # 200 lines of code...
end
```

### Error Handling

```ruby
# Good: Fail loudly on data-loss risks
def load(locale)
  # ...
rescue JSON::ParserError => e
  raise Error,
        "Corrupted state file: #{e.message}\n" \
        "This would cause state loss. Fix the JSON manually or restore from git."
end

# Bad: Swallowing errors / silently resetting state
def load(locale)
  JSON.parse(File.read(file))
rescue StandardError
  {}
end
```

### State Files

```ruby
# Good: Idempotent, POSIX-conformant writes
content = "#{JSON.pretty_generate(keys.sort.to_h)}\n"
next if File.exist?(state_file) && File.read(state_file) == content
File.write(state_file, content)

# Bad: Newline-less output, unconditional rewrites (diff churn)
File.write(state_file, JSON.pretty_generate(keys))
```

### API Keys

```ruby
# Good: Resolve lazily, never persist or log
config.openai_api_key = -> { AppConf.openai_key }

# Bad: Interpolating keys into logs or error messages
logger.info "Using key #{api_key}"
```

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Methods are small (<30 lines ideal, <50 max)
- [ ] Files are focused (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Errors raise `Locallingo::Error` with actionable messages; no silent state loss
- [ ] State writes are idempotent and end with a trailing newline
- [ ] No API keys stored, logged, or committed
- [ ] Rubocop passes (`bundle exec rake rubocop`)
