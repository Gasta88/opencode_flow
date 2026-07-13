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
    ↓  /review-spec FEAT-123             (human approval gate; skipped for --quick)
    ↓  /implement-spec FEAT-123
Code changes + tests                     ← spec re-read before every file edit
    ↓  /create-pr "<title>"
PR

decisions.md                             ← cross-issue architectural decisions (repo root)
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
| `/implement-spec <KEY>` | `opencode/qwen3.5-plus` | `@spec-implementer` (qwen3.6-plus) | After spec is reviewed and approved |
| `/review-spec <KEY> [--visual]` | `opencode/qwen3.6-plus` | `@spec-analyst` (on revision) | Human-gated review of a generated spec before implementation |
| `/review-code` | `opencode/qwen3.5-plus` | `@code-reviewer` then `@code-review-filter` | Adversarial review of current diff |
| `/implement-loop <KEY> [--max-passes N]` | `opencode/qwen3.5-plus` | `@spec-implementer` + `@dod-evaluator` | After spec is complete — loops until DoD passes or budget exhausted |
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
| `dod-evaluator` | qwen3.5-plus | subagent (hidden) | Binary PASS/FAIL verdict on DoD items |

---

## Spec-as-attention-anchor and loop governance (no native hooks)

OpenCode does not have Claude-Code-style Stop hooks or `/goal`.
Equivalent behaviour is enforced two ways:

**Prompt-level (all commands):**
- `spec-implementer` re-reads the spec before every file edit.
- `spec-implementer` blocks completion until every DoD checkbox is satisfied.

**Loop-level (`/implement-loop` only):**
- `dod-evaluator` provides independent PASS/FAIL verdicts after each implementer pass.
- The dispatcher re-enters `spec-implementer` with targeted failure context until PASS or budget exhausted.
- This replicates the `/goal` + separate evaluator pattern within OpenCode's command model.

For true event-driven enforcement on every tool call, implement an OpenCode plugin
using `tool.execute.before` / `tool.execute.after` — see https://opencode.ai/docs/plugins/

---

## Cross-Issue Knowledge: decisions.md

`decisions.md` is a repo-root file that persists architectural rulings across
issues. It ensures that decisions made during one issue are visible and
enforceable during future unrelated issues.

### Location
Repo root: `decisions.md`

### Format
Each entry follows this structure:

```markdown
## <YYYY-MM-DD> — <short title>
Issue: <ISSUE-KEY>
Decision: <one paragraph>
Rationale: <why>
Alternatives considered: <what was rejected and why>
Scope: <repo-wide | subsystem-name | specific-files>
```

### Read Contract
| Agent | When | Purpose |
|-------|------|---------|
| `spec-analyst` | Before Phase 3 | Apply scoped decisions as constraints in the Technical Specification |
| `spec-analyst-quick` | Before Phase 2 | Apply scoped decisions as constraints in the compact spec |
| `code-reviewer` | Optional (within 3-lookup budget) | Flag diffs that contradict recorded decisions |

### Write Contract
| Agent | When | Condition |
|-------|------|-----------|
| `spec-analyst` | After Phase 6 | Only when the spec introduced a decision with repo-wide or cross-feature scope |
| `spec-analyst-quick` | **Never** | Quick fixes do not generate architectural precedent |

### Size Management
`decisions.md` must remain small enough to read in a single context window.
Pruning and sectioning strategies are noted as future work.
