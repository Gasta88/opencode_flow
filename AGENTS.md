# AGENTS.md — Spec-Driven Workflow Baseline Rules

These rules apply to all agents in this repository. Skills layer on top; they do not replace these rules.

## Rule 1 — Spec-First Changes

No code is written without a spec. Every change begins as a light spec file in
`specs/`, is analyzed via `/analyze-issue`, and produces a structured
`issue-{KEY}-spec.md` before `/implement-spec` or `/implement-loop` is invoked.
The only exception is `--quick` mode for trivial bugs and typos, which still
produces a compact spec.

Light spec files can be created manually or sourced from a GitHub issue by passing a bare number to `/brainstorm`, `/analyze-issue`, or `/letsgo`. A purely numeric first argument is always a GitHub issue reference.

## Rule 2 — Skill Loading

Always load the `spec-driven-workflow` skill at the start of any session that
involves spec analysis, implementation, or review. The skill defines the 3-file
persistence pattern, command dispatch table, and subagent roles.

```
Load skill: spec-driven-workflow
```

## Rule 3 — Consult decisions.md

Before drafting a technical specification or making an architectural choice,
read `decisions.md` at the repo root (if it exists). Any decision entry whose
Scope covers the files or subsystems you are working on is a constraint — do
not re-derive the choice. Record which decisions apply in your spec's Technical
Specification section.

## Rule 4 — Spec as Attention Anchor

During implementation, the spec is the single source of truth. If the codebase
and the spec conflict, the spec wins (unless there is a technical blocker — in
which case, log it in `progress.md` under `## Errors`).

## Rule 5 — Progress is Always Current

Update `issue-{KEY}-progress.md` after every phase completion and every error.
A checkbox that is not checked means the phase is not done.

## Rule 6 — Definition of Done is a Gate

Do not declare implementation complete until every checkbox in the spec's
`## Definition of Done` section is satisfied. If any item is unmet, continue
working or log the blocker in `progress.md`.

## Rule 7 — Evidence is the gate

A progress checkbox without an `Evidence:` line is not done. Every checked box must carry an `Evidence:` sub-line: test command + output, run-log excerpt, or a note that verification was not possible. A checked box with no `Evidence:` line counts as unchecked.

## Rule 8 — Decide, don't guess

On a judgment call, consult root `decisions.md` first. If no decision covers
the case, escalate via the three-option protocol from the `spec-driven-workflow`
skill (`🔀 Decision needed:` with Option A / Option B / Recommended). Record
the ruling as a dated block appended to `decisions.md`. Never invent a
decision silently.
