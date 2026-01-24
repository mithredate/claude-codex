---
name: claude-md-helper
description: Help write and improve CLAUDE.md files for Claude Code projects. Use when users want to create a new CLAUDE.md, improve an existing one, review their CLAUDE.md for best practices, or ask questions about what to include in CLAUDE.md. Triggers on requests like "help me write a CLAUDE.md", "review my CLAUDE.md", "what should I put in CLAUDE.md", or "improve my Claude configuration".
---

# CLAUDE.md Helper

Guide users in creating effective CLAUDE.md files that maximize Claude Code's performance.

## Core Principle

CLAUDE.md is the agent's primary source of truth for how a repository works. It's a high-leverage configuration point—a poorly written CLAUDE.md can degrade performance across all sessions.

## The WHAT-WHY-HOW Framework

Structure CLAUDE.md around three dimensions:

1. **WHAT**: Tech stack, project structure, codebase map (critical for monorepos)
2. **WHY**: Purpose of project components and their relationships
3. **HOW**: Workflows, build commands, verification methods, testing procedures

## Length Guidelines

- **Target**: Under 300 lines (60 lines is ideal)
- **Rationale**: LLMs can follow ~150-200 instructions consistently. Claude Code's system prompt uses ~50, leaving limited headroom
- **Effect of bloat**: Instruction-following degrades uniformly as count increases—Claude starts ignoring ALL instructions, not just new ones

## What to Include

```markdown
# Build commands
- npm run build: Build the project
- npm run test: Run tests
- npm run typecheck: Run typechecker

# Code style (brief!)
- Use ES modules (import/export), not CommonJS
- Destructure imports when possible

# Workflow
- Typecheck after code changes
- Run single tests, not full suite

# Project structure
src/
├── components/   # React components
├── lib/          # Shared utilities
└── api/          # API routes
```

## What NOT to Include

1. **Task-specific instructions** - Claude ignores content not relevant to current task
2. **Linting rules** - Use actual linters; LLMs are slow and expensive for this
3. **Code snippets** - They go stale; use `file:line` references instead
4. **Auto-generated content** - Carefully craft this file; don't rely on `/init`

## Progressive Disclosure Pattern

For complex projects, keep task-specific docs in separate files:

```text
agent_docs/
├── building_the_project.md
├── running_tests.md
├── code_conventions.md
└── database_schema.md
```

Reference in CLAUDE.md:

```markdown
## Testing
See agent_docs/running_tests.md for testing guide.
```

## Monorepo Placement

- **Root**: Shared context for all work
- **Subdirectories**: Pulled in when working in that directory (e.g., `frontend/CLAUDE.md`)
- **Home folder** (`~/.claude/CLAUDE.md`): Personal preferences across all projects

## Workflow for Creating/Improving CLAUDE.md

1. **Read existing file** (if any) to understand current state
2. **Identify gaps** using the WHAT-WHY-HOW framework
3. **Check length** - If over 300 lines, extract to reference files
4. **Remove** task-specific, stale, or linting content
5. **Add directory map** if missing
6. **Define workflows** for common tasks

See [references/checklist.md](references/checklist.md) for quick validation.
See [references/examples.md](references/examples.md) for templates and patterns.
