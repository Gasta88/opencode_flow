---
name: spec-driven-workflow
description: Use when working with light spec files, generating specs, or implementing from spec files. Defines the 3-file persistence pattern, the spec lifecycle commands, Core Rules, and loop governance.
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
- Run-log excerpt: `Evidence: npm run build — compiled successfully, 0 errors`
- Explicit negative: `Evidence: no verification possible because no test runner is configured`

### 2. Data before analysis

Never analyse what you have not read. Fetch raw data into `findings.md` before drawing any conclusions.

### 3. Spec before code

No code is written without a spec. Every change begins as a light spec file, is analyzed via `/analyze-issue`, and produces a structured `issue-{KEY}-spec.md` before `/implement-spec` or `/implement-loop` is invoked.

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

| Command | Dispatcher | Delegates to |
|---------|-----------|--------------|
| `/analyze-issue <path>` | `opencode/qwen3.5-plus` | `@spec-analyst` (qwen3.6-plus) |
| `/analyze-issue <path> --quick` | `opencode/qwen3.5-plus` | `@spec-analyst-quick` (qwen3.5-plus) |
| `/brainstorm <path>` | `opencode/qwen3.6-plus` | — (inline) |
| `/implement-spec <KEY>` | `opencode/qwen3.5-plus` | `@spec-implementer` (qwen3.6-plus) |
| `/review-spec <KEY> [--visual]` | `opencode/qwen3.6-plus` | `@spec-analyst` (on revision) |
| `/review-code [--max-fix-passes N]` | `opencode/qwen3.5-plus` | `@code-reviewer` → `@code-review-filter` → `@code-fixer` |
| `/implement-loop <KEY> [--max-passes N]` | `opencode/qwen3.5-plus` | `@spec-implementer` + `@dod-evaluator` |
| `/create-pr "<title>"` | `opencode/qwen3.5-plus` | — (inline) |
| `/handover` | `opencode/qwen3.6-plus` | — (inline) |
| `/letsgo <path> [--quick] [--headless] [...]` | `opencode/qwen3.6-plus` | all above, chained |

---

## Subagents

| Agent | Mode | Role |
|-------|------|------|
| `spec-analyst` | subagent | Full 6-phase spec generation |
| `spec-analyst-quick` | subagent | 2-phase compact spec |
| `spec-implementer` | subagent | Implements from spec, tracks progress |
| `code-fixer` | subagent (hidden) | Surgical fixer — applies review findings |
| `code-reviewer` | subagent (hidden) | Adversarial diff review |
| `code-review-filter` | subagent (hidden) | Filters reviewer findings |
| `dod-evaluator` | subagent (hidden) | Binary PASS/FAIL on DoD items |
| `spec-conflict-checker` | subagent (hidden) | CLEAR/CONFLICTS verdict on spec vs decisions.md + codebase |
| `external-scout` | subagent (hidden) | Fetches current docs for external dependencies |

---

## Loop governance

OpenCode does not have Claude-Code-style Stop hooks or `/goal`.
Loop behaviour is enforced via:

**Prompt-level:**
- `spec-implementer` follows the spec as the single source of truth.
- `spec-implementer` blocks completion until every DoD checkbox is satisfied.

**Loop-level (`/implement-loop` only):**
- `dod-evaluator` provides independent PASS/FAIL verdicts after each implementer pass.
- The dispatcher re-enters `spec-implementer` with targeted failure context until PASS or budget exhausted.

**Loop-level (`/letsgo` only):** three independent bounded loops, chained:
- Spec-conflict loop: `spec-conflict-checker` gives CLEAR/CONFLICTS verdicts;
  `spec-analyst` revises on CONFLICTS, up to `--max-spec-turns` (default 3).
  Unresolved after budget → falls through to the same human approve/request-changes/reject
  gate `/review-spec` uses, since automation cannot force-close a genuine
  ambiguity. Under `--headless`, unresolved conflicts stop the pipeline and mark the issue as Blocked.
- Implementation loop: identical to `/implement-loop`'s, budget `--max-impl-passes`
  (default 3). Unresolved after budget → asks the human whether to continue or stop.
  Under `--headless`, critical DoD failures stop the pipeline.
- Code-review remediation loop: `code-reviewer` + `code-review-filter` produce
  findings; `code-fixer` applies them (falling back to `spec-implementer` if spec context is needed); re-review until clean or
  `--max-fix-passes` (default 3). Unresolved after budget → asks the human
  whether to continue or stop. Under `--headless`, residual findings stop the pipeline (no PR opened).

**Test gate (`/letsgo` only):** Runs after implementation, before code review.
With `--strict-tests` (default under `--headless`), test failures after the fix budget stop the pipeline (no PR opened). Without it, failures are logged but the pipeline continues. A post-review test re-run catches regressions from code-fixer changes before PR creation.

For event-driven enforcement on every tool call, implement an OpenCode plugin
using `tool.execute.before` / `tool.execute.after` — see https://opencode.ai/docs/plugins/

---

## Progress Tracking: Engram (Primary) + Markdown (Fallback)

Agents use Engram MCP tools for progress tracking by default, falling back to
Markdown files when Engram is unavailable.

### Topic Key Convention

Every `topic_key` must include the ISSUE_KEY prefix to prevent collisions:

| Pattern | topic_key example | Scope |
|---------|-------------------|-------|
| Implementation progress | `impl/FEAT-123/progress` | project |
| Test cycles | `impl/FEAT-123/test-cycles` | project |
| Errors | `impl/FEAT-123/errors` | project |
| Loop passes | `loop/FEAT-123/passes` | project |
| Pipeline audit trail | `pipeline/FEAT-123/<stage>` | project |
| Human review | `review/FEAT-123/human-approval` | project |
| Cross-issue decisions | `decision/FEAT-123/<slug>` | global |

### Scope Conventions

- `project` (default): Issue-specific progress, test results, errors, review logs
- `global`: Cross-issue decisions that benefit other teams or sessions
- `personal`: User preferences or agent-specific conventions (rarely used)

### Fallback Behavior

If Engram MCP tools are unavailable or return an error:
1. Log the error and continue (do not crash)
2. Fall back to Markdown writes in `specs/issue-{KEY}-progress.md`
3. Use the same structure (checkboxes, evidence lines, tables) as before

### Markdown Files That Remain

These files are NOT replaced by Engram (they need git history and reviewability):
- `specs/issue-{KEY}-findings.md` — raw light spec data
- `specs/issue-{KEY}-spec.md` — implementation contract
- `specs/issue-{KEY}-progress.md` — fallback when Engram unavailable
- `decisions.md` — git source of truth (Engram mirrors with `scope: global`)
- `specs/issue-{KEY}-extdocs.md` — external dependency docs

---

## Cross-Issue Knowledge: decisions.md

`decisions.md` persists architectural rulings across issues. Read before drafting specs (AGENTS.md Rule 3).

`spec-analyst` writes a decision entry after Phase 6 only if the spec introduces a repo-wide or cross-feature decision. `spec-analyst-quick` never writes decisions.

When writing a decision, also call `mem_save` with `scope: global` and a `topic_key` like `decision/ISSUE_KEY/<slug>` for cross-project searchability. The file remains the git source of truth; Engram provides search and compaction resilience.
