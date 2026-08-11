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

## Rationalizations

When an agent (or a human) offers an excuse to skip a step, apply the matching rebuttal:

| Excuse | Rebuttal |
|--------|----------|
| "I already understand the light spec file, no need to read it again." | Understanding ≠ evidence. Read it, write findings.md, then proceed. |
| "I'll fill in the Evidence lines at the end." | Evidence recorded after the fact is unreliable. Log it as you go. |
| "The spec is vague here — I'll just do what makes sense." | Vague spec → Decision Escalation Protocol. Do not invent requirements. |
| "This is a small change, I can skip the test run." | Small changes cause regressions. Run the test command or log why you cannot. |
| "I've seen this pattern before, I know the API." | APIs change. If extdocs exist, read them. If not, verify with a lookup. |

---

## Commands

| Command | Dispatcher model | Delegates to | When to use |
|---------|------------------|--------------|-------------|
| `/analyze-issue <path>` | `opencode/qwen3.5-plus` | `@spec-analyst` (qwen3.6-plus) | Stories, features, complex bugs |
| `/analyze-issue <path> --quick` | `opencode/qwen3.5-plus` | `@spec-analyst-quick` (qwen3.5-plus) | Minor bugs, config changes, typos |
| `/brainstorm <path>` | `opencode/qwen3.6-plus` | — (runs inline) | Pre-spec ideation — produces a light spec file for `/analyze-issue` to consume |
| `/implement-spec <KEY>` | `opencode/qwen3.5-plus` | `@spec-implementer` (qwen3.6-plus) | After spec is reviewed and approved |
| `/review-spec <KEY> [--visual]` | `opencode/qwen3.6-plus` | `@spec-analyst` (on revision) | Human-gated review of a generated spec before implementation |
| `/review-code [--max-fix-passes N]` | `opencode/qwen3.5-plus` | `@code-reviewer` → `@code-review-filter` → `@code-fixer` (loop) | Adversarial review of current diff with bounded fix loop |
| `/implement-loop <KEY> [--max-passes N]` | `opencode/qwen3.5-plus` | `@spec-implementer` + `@dod-evaluator` | After spec is complete — loops until DoD passes or budget exhausted |
| `/create-pr "<title>"` | `opencode/qwen3.5-plus` | — (runs inline) | Open a PR with structured description |
| `/handover` | `opencode/qwen3.6-plus` | — (runs inline) | Async handover document |
| `/letsgo <path> [--quick] [--max-spec-turns N] [--max-impl-passes N] [--max-fix-passes N]` | `opencode/qwen3.6-plus` | all of the above, inlined | Full pipeline: analyze → auto-resolve spec conflicts (human escalation after budget) → implement (DoD loop or single pass) → adversarial review + remediation loop → PR |

---

## Subagents

| Agent | Model | Mode | Role |
|-------|-------|------|------|
| `spec-analyst` | qwen3.6-plus | subagent | Full 6-phase spec generation |
| `spec-analyst-quick` | qwen3.5-plus | subagent | 2-phase compact spec |
| `spec-implementer` | qwen3.6-plus | subagent | Implements from spec, tracks progress |
| `code-fixer` | deepseek-v4-flash | subagent (hidden) | Surgical fixer — applies review findings one at a time |
| `code-reviewer` | kimi-k2.7-code | subagent (hidden) | Adversarial diff review |
| `code-review-filter` | qwen3.5-plus | subagent (hidden) | Filters reviewer findings |
| `dod-evaluator` | deepseek-v4-flash | subagent (hidden) | Binary PASS/FAIL verdict on DoD items |
| `spec-conflict-checker` | deepseek-v4-flash | subagent (hidden) | Binary CLEAR/CONFLICTS verdict on a spec vs decisions.md and the codebase — used by `/letsgo` |
| `external-scout` | qwen3.5-plus | subagent (hidden) | Fetches current docs for external dependencies listed in specs |

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
  ambiguity.
- Implementation loop: identical to `/implement-loop`'s, budget `--max-impl-passes`
  (default 3). Unresolved after budget → asks the human whether to continue or stop.
- Code-review remediation loop: `code-reviewer` + `code-review-filter` produce
  findings; `code-fixer` applies them (falling back to `spec-implementer` if spec context is needed); re-review until clean or
  `--max-fix-passes` (default 3). Unresolved after budget → asks the human
  whether to continue or stop.

For event-driven enforcement on every tool call, implement an OpenCode plugin
using `tool.execute.before` / `tool.execute.after` — see https://opencode.ai/docs/plugins/

---

## Cross-Issue Knowledge: decisions.md

`decisions.md` is a repo-root file that persists architectural rulings across
issues. See AGENTS.md Rule 3 for the read contract.

### Write Contract
| Agent | When | Condition |
|-------|------|-----------|
| `spec-analyst` | After Phase 6 | Only when the spec introduced a decision with repo-wide or cross-feature scope |
| `spec-analyst-quick` | **Never** | Quick fixes do not generate architectural precedent |
