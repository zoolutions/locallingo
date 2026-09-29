# Agent Orchestration Rules

## Available Agents

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| Explore (`model: haiku`) | Codebase exploration | Finding files, understanding patterns |
| Plan (`model: sonnet`) | Implementation planning | Complex features, architectural decisions |
| general-purpose (`model: sonnet`) | Multi-step tasks | Research, complex searches |
| `fable-validator` (`model: fable`, pinned) | Final validation | A finished change, before its pull request opens |

Every spawned agent names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL` in `.claude/settings.json`).

## Immediate Agent Usage

Use agents PROACTIVELY without waiting for user prompt:

1. **Complex feature requests** -> Use Plan agent first
2. **Codebase exploration** -> Use Explore agent
3. **Multi-file searches** -> Use Explore agent (not direct Glob/Grep)
4. **Architectural decisions** -> Use Plan agent

## Parallel Execution

**ALWAYS** use parallel Task execution for independent operations:

```markdown
# GOOD: Parallel execution
Launch multiple agents simultaneously:
1. Agent 1: Explore manager/state patterns
2. Agent 2: Check validator patterns
3. Agent 3: Review test coverage

# BAD: Sequential when unnecessary
First explore, wait, then check patterns, wait, then review...
```

## When to Use Explore Agent

Use the Explore agent (subagent_type=Explore, `model: haiku`) instead of direct Glob/Grep when:
- Open-ended codebase exploration
- Searching for patterns across CLI, manager, state, validator, and quality layers
- Answering questions about codebase structure
- Finding related implementations across modules

## When NOT to Use Agents

Use direct tools when:
- Reading a specific known file path
- Simple pattern match in known location
- Single-file edits
- Running specific commands
