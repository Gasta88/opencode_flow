# AGENTS.md — Spec-Driven Workflow Baseline Rules

These rules apply to all agents in this repository. Skills layer on top; they do not replace these rules.

## Rule 1 — Spec-First Changes

No code without a spec: a light spec in `specs/` or a GitHub issue → `/analyze-issue` → `issue-{KEY}-spec.md` → `/implement-spec` or `/implement-loop`. `--quick` is only for trivial bugs/typos and still produces a compact spec. A bare numeric first argument to `/analyze-issue` or `/letsgo` is always a GitHub issue. At project scope, `/brainstorm <notion-url>` publishes light issues on a Project board and routes each slice to the Foundry or human lane.

## Rule 2 — Skill Loading

Load the `spec-driven-workflow` skill at the start of any spec analysis, implementation, or review session.

## Rule 3 — Consult decisions.md

Before drafting a spec or architectural choice, read root `decisions.md` (if present). Entries whose Scope covers your files are constraints — do not re-derive them. Record applicable decisions in the spec's Technical Specification.

## Rule 4 — Spec as Attention Anchor

The spec is the single source of truth. If code and spec conflict, the spec wins unless there is a technical blocker — log it in `progress.md` under `## Errors`.

## Rule 5 — Progress is Always Current

Update `issue-{KEY}-progress.md` after every phase and every error. An unchecked box means the phase is not done.

## Rule 6 — Definition of Done is a Gate

Do not declare implementation complete until every `## Definition of Done` checkbox is satisfied. Otherwise continue or log the blocker in `progress.md`.

## Rule 7 — Evidence is the Gate

Every checked progress box needs an `Evidence:` line: test command + output, run-log excerpt, or a note that verification was impossible. No `Evidence:` line = unchecked.

## Rule 8 — Decide, don't guess

If `decisions.md` doesn't cover a judgment call, escalate with the `spec-driven-workflow` three-option protocol (`🔀 Decision needed:`) and append the dated ruling to `decisions.md`. Never invent a decision.

## Rule 9 — Engram: Save Progress, Not Just Files

Use `mem_save` / `mem_update` / `mem_session_summary` for progress; Markdown stays for git-tracked contracts. Topic keys are namespaced by ISSUE_KEY (`impl/FEAT-123/progress`) — see the skill's topic-key table. If Engram fails, fall back to `progress.md`, log the error, and continue. Engram is best-effort: Foundry-fit issue bodies must be self-contained because the sandbox cannot reach Engram.

## Rule 10 — Engram: Search Before Assuming

Before re-deriving prior work, `mem_search` with task keywords; for recall requests use `mem_context` then `mem_search`.
