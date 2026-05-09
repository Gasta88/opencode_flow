---
name: spec-driven-workflow
description: Use when working with light spec files, generating specs, or implementing from spec files. Defines the 3-file persistence pattern and the spec lifecycle commands.
---

# Spec-Driven Workflow

## The Lifecycle

```
Light Spec File
    ↓  /analyze-issue FEAT-123           (or --quick for small issues)
specs/issue-FEAT-123-findings.md         ← raw file data
specs/issue-FEAT-123-progress.md         ← phase tracking
specs/issue-FEAT-123-spec.md             ← structured spec
    ↓  /implement-spec FEAT-123
Code changes + tests                     ← spec re-read before every file edit
    ↓  /create-pr "<title>"
PR
```

---

## The 3-File Pattern

Every light feature spec gets exactly three files, all inside `specs/`:

| File | Purpose | Written |
|------|---------|---------|
| `issue-{KEY}-findings.md` | Verbatim light spec file content + raw codebase notes | **First** — before any analysis |
| `issue-{KEY}-progress.md` | Phase checkboxes and error log | Initialized at start, updated each phase |
| `issue-{KEY}-spec.md` | The structured implementation spec | Last — assembled section by section |

---

## Core Rules

**Data before analysis.**
After reading the light spec file → write findings.md immediately, before reasoning over the data.
If analysis fails mid-way, the data is safe and the agent can resume.

**Spec before code.**
`specs/issue-{KEY}-spec.md` must be complete before `/implement-spec` is run.

**Spec as attention anchor.**
During implementation, the agent re-reads the relevant spec section before every file edit.
The spec is the single source of truth. Code follows spec, not the other way around.

**Progress is always current.**
Every phase completion and every error gets logged to progress.md immediately.
A checkbox that is not checked means the phase is not done.

---

## Commands

| Command | Dispatcher model | Delegates to | When to use |
|---------|------------------|--------------|-------------|
| `/analyze-issue <path>` | `opencode/qwen3.5-plus` | `@spec-analyst` (qwen3.6-plus) | Stories, features, complex bugs |
| `/analyze-issue <path> --quick` | `opencode/qwen3.5-plus` | `@spec-analyst-quick` (qwen3.5-plus) | Minor bugs, config changes, typos |
| `/implement-spec <KEY>` | `opencode/qwen3.5-plus` | `@spec-implementer` (qwen3.6-plus) | After spec is complete |
| `/review-code` | `opencode/qwen3.5-plus` | `@code-reviewer` then `@code-review-filter` | Adversarial review of current diff |
| `/create-pr "<title>"` | `opencode/qwen3.5-plus` | — (runs inline) | Open a PR with structured description |
| `/handover` | `opencode/qwen3.6-plus` | — (runs inline) | Async handover document |

---

## Subagents

| Agent | Model | Mode | Role |
|-------|-------|------|------|
| `spec-analyst` | qwen3.6-plus | subagent | Full 6-phase spec generation |
| `spec-analyst-quick` | qwen3.5-plus | subagent | 2-phase compact spec |
| `spec-implementer` | qwen3.6-plus | subagent | Implements from spec, tracks progress |
| `code-reviewer` | kimi-k2.5 | subagent (hidden) | Adversarial diff review |
| `code-review-filter` | qwen3.5-plus | subagent (hidden) | Filters reviewer findings |

---

## Spec-as-attention-anchor (no native hooks)

OpenCode does not have Claude-Code-style PreToolUse / PostToolUse / Stop bash hooks.
Equivalent behaviour is enforced **inside the agent prompts** instead:

- `spec-implementer` is instructed to re-read the relevant spec section before every file edit.
- `spec-implementer` blocks completion until every Definition-of-Done checkbox is satisfied.
- Progress is updated after every sub-task.

If you want true event-driven enforcement (e.g. injecting reminders on every edit),
implement it as an OpenCode plugin using `tool.execute.before` / `tool.execute.after` —
see https://opencode.ai/docs/plugins/ . Until then, treat the rules above as
agent-prompt obligations, not infrastructure.
