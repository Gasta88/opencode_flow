---
name: spec-driven-workflow
description: Use when working with light spec files, generating specs, or implementing from spec files. Defines the 3-file persistence pattern and the spec lifecycle commands.
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

## Loop governance

OpenCode does not have Claude-Code-style Stop hooks or `/goal`.
Loop behaviour is enforced via:

**Prompt-level:**
- `spec-implementer` follows the spec as the single source of truth.
- `spec-implementer` blocks completion until every DoD checkbox is satisfied.

**Loop-level (`/implement-loop` only):**
- `dod-evaluator` provides independent PASS/FAIL verdicts after each implementer pass.
- The dispatcher re-enters `spec-implementer` with targeted failure context until PASS or budget exhausted.

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
