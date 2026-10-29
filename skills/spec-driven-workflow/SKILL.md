---
name: spec-driven-workflow
description: Use when analyzing light specs or implementing/reviewing from specs — 3-file pattern, commands, loop rules.
---

# Spec-Driven Workflow

## The 3-File Pattern

Every light feature spec generates exactly three files in `specs/`:

| File | Purpose |
|------|---------|
| `issue-{KEY}-findings.md` | Raw light spec content (verbatim) |
| `issue-{KEY}-progress.md` | Phase checkboxes, implementation progress, and error log |
| `issue-{KEY}-spec.md` | Structured implementation spec with requirements, technical details, test strategy, and definition of done |

---

## Core Rules

These rules apply to every agent in this workflow. They are non-negotiable.

### 1. Evidence over assertion

A phase checkbox in `progress.md` is **not complete** unless it carries an `Evidence:` sub-line documenting what was done and what the result was. A checked box with no `Evidence:` line counts as unchecked.

Evidence takes one of these forms:
- Test command + result: `Evidence: pytest tests/ — 14 passed`
- Run-log excerpt or explicit negative (verification impossible)

### 2. Data before analysis

Never analyse what you have not read. Fetch raw data into `findings.md` before drawing any conclusions.

### 3. Spec before code

No code is written without a spec. Every change begins as a light spec, is analyzed via `/analyze-issue`, and produces a structured `issue-{KEY}-spec.md` before `/implement-spec` or `/implement-loop` is invoked.

A light spec is either a file under `specs/` or a GitHub issue. `/brainstorm` publishes light specs as GitHub issues and routes each one to the Foundry or the human lane; `/analyze-issue <N>` materializes issue `N` into `specs/{N}.md` before analyzing it.

### 4. Spec as anchor

During implementation, the spec is the single source of truth. If the codebase and the spec conflict, the spec wins — unless there is a technical blocker. In that case, log it in `progress.md` under `## Errors`.

### 5. Progress is always current

Update `issue-{KEY}-progress.md` after every phase completion and every error. A checkbox that is not checked means the phase is not done.

---

## Decision Escalation Protocol

When a judgment call has no clear answer from the spec, the codebase, or `decisions.md`, use this protocol. **Shared by `spec-analyst`, `spec-implementer`, and `/letsgo`.**

```
🔀 Decision needed: <describe the choice>
  Option A: <first option>
  Option B: <second option>
  Recommended: <A or B, with one-sentence rationale>
```

After the user selects (or if no user is available and the agent must proceed):

1. Record the ruling as a **dated block** appended to the repo-root `decisions.md`:

```markdown
## YYYY-MM-DD — <short title>

Issue: <ISSUE_KEY or "general">
Decision: <what was chosen>
Rationale: <why>
Alternatives considered: <what was rejected>
Scope: <files/subsystems affected>
```

2. Note in `progress.md` which decision entry applies.

Do not create `specs/decisions.md`. Do not use `DEC-NNN` identifiers. The repo-root `decisions.md` with dated-block format is the only convention.

---

## Commands

| Command | Delegates to |
|---------|--------------|
| `/analyze-issue <path> [--quick]` | `@spec-analyst` / `@spec-analyst-quick` |
| `/brainstorm <notion-url>` | inline (human-in-the-loop; routes slices to Foundry/human) |
| `/implement-spec <KEY> [--max-parallel N]` | `@spec-implementer` (parallel frontier waves when N > 1) |
| `/review-spec <KEY> [--visual]` | `@spec-analyst` (on revision) |
| `/review-code [...]` | `@code-reviewer` + `@standards-reviewer` + `@spec-fidelity-reviewer` → `@code-review-filter` → `@code-fixer` / `@spec-implementer` |
| `/implement-loop <KEY> [--max-passes N]` | `@spec-implementer` + `@dod-evaluator` |
| `/create-pr`, `/handover`, `/retro` | inline |
| `/letsgo <path> [...]` | all above, chained |

## Loop governance

- `spec-implementer`: spec is source of truth; red-green at declared seams; blocks completion until every DoD checkbox passes.
- `/implement-loop`: `dod-evaluator` PASS/FAIL after each pass; re-enter with failure context until PASS or budget.
- `/letsgo` spec-conflict loop: `spec-conflict-checker` → `spec-analyst` revision, `--max-spec-turns` (3); unresolved → human gate (headless: stop, Blocked).
- `/letsgo` implementation loop: as `/implement-loop`, `--max-impl-passes` (3); unresolved → ask human (headless: stop on critical DoD failure).
- `/letsgo` review loop: three parallel reviewers → `code-review-filter` (per-axis, no rerank) → `code-fixer` (bugs/standards) / `spec-implementer` (spec), `--max-fix-passes` (3); unresolved → ask human (headless: stop, no PR).
- `/implement-spec --max-parallel N`: ready-frontier waves of pairwise-disjoint `Files` sets; `/implement-loop` and `/letsgo` stay sequential.
- Test gate (`/letsgo`): after implementation, before review; `--strict-tests` (default headless) stops on failure, else logs; post-review re-run catches regressions.

---

## Progress Tracking: Engram (Primary) + Markdown (Fallback)

Use Engram for progress; if it errors, log and continue with `specs/issue-{KEY}-progress.md` using the same checkboxes and `Evidence:` lines.

### Topic Key Convention

Every `topic_key` carries a namespace prefix — ISSUE_KEY for issue work, PROJECT_SLUG for `/brainstorm`:

| Pattern | topic_key example | Scope |
|---------|-------------------|-------|
| Vision source / decisions / breakdown | `vision/my-project/{source,decisions,breakdown}` | project |
| Implementation progress / test cycles / errors | `impl/FEAT-123/{progress,test-cycles,errors}` | project |
| Loop passes | `loop/FEAT-123/passes` | project |
| Pipeline audit trail | `pipeline/FEAT-123/<stage>` | project |
| Human review | `review/FEAT-123/human-approval` | project |
| Cross-issue decisions | `decision/FEAT-123/<slug>` | global |

Scopes: `project` (default), `global` (cross-issue decisions), `personal` (rare).

### Markdown files that remain

Git-tracked contracts: `specs/issue-{KEY}-{findings,spec,progress,extdocs}.md` and `decisions.md`.

`/brainstorm` writes no Markdown: its durable artifacts are the GitHub issues it publishes. Foundry-fit issue bodies are self-contained because the sandbox cannot reach Engram.

---

## Cross-Issue Knowledge: decisions.md

Read `decisions.md` before drafting specs (AGENTS.md Rule 3). `spec-analyst` writes an entry after Phase 6 only for repo-wide/cross-feature decisions; `spec-analyst-quick` never writes. Also `mem_save` with `scope: global` and `topic_key: decision/ISSUE_KEY/<slug>` — the file remains the git source of truth.
