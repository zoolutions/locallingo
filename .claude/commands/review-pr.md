---
description: Review a GitHub pull request for code quality, patterns, and best practices
model: opus
argument-hint: "PR URL or number (e.g., 5 or https://github.com/zoolutions/locallingo/pull/5)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(bundle exec:*), Bash(git:*), Read, Glob, Grep
---

# PR Review

Review PR for pattern compliance and issues. Be concise.

## Workflow

1. Fetch PR details and diff via `gh pr view` / `gh pr diff`
2. Categorize files by type
3. Check for pattern violations
4. Output structured review

## Pattern Violations to Check

```ruby
# WRONG -> RIGHT
Version bump in version.rb          -> Remove; rake release[x.y.z] owns it
Silently resetting corrupted state  -> Raise Locallingo::Error
Dropping manual flags on sync       -> Preserve hand-edit protection
Rewriting unchanged state files     -> Skip byte-identical writes
State files without final newline   -> Append trailing "\n"
API keys in logs/errors/files       -> Lazy resolution, never persisted
Hardcoded app-specific behavior     -> Drive from .locallingo.yml
Real LLM/network calls in specs     -> Mock the provider
Breaking legacy CLI flag forms      -> Keep them working with deprecation notice
rescue StandardError => nil         -> Specific error handling
```

## Output Format

```
## Files Requiring Manual Review

| File | Reason |
|------|--------|
| lib/locallingo/state_store.rb | State-format change, verify upgrade story |
| lib/locallingo/manager.rb | Sync path, verify manual-flag preservation |

## Critical Issues

- `lib/locallingo/state_store.rb:45` - Unconditional rewrite causes diff churn
- `lib/locallingo/cli.rb:12` - Legacy flag form removed without deprecation

## Suggestions (non-blocking)

- Consider extracting X to shared module

## Verdict

**Request Changes** - Fix state safety before merge
```

## Tools

```
gh pr view <PR> --json title,body,state,files  -> PR details + file list
gh pr diff <PR>                                -> Changes
gh pr checks <PR>                              -> CI status

bundle exec rake rubocop  -> Style checks
bundle exec rspec         -> Tests
```
