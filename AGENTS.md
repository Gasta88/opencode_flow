# AGENTS.md — Spec-Driven Workflow Baseline Rules

These rules apply to all agents in this repository. Skills layer on top; they do not replace these rules.

## Rule 1 — Spec-First Changes

No code is written without a spec. Every change begins as a light spec — a file
in `specs/` or a GitHub issue — is analyzed via `/analyze-issue`, and produces a
structured `issue-{KEY}-spec.md` before `/implement-spec` or `/implement-loop`
is invoked. The only exception is `--quick` mode for trivial bugs and typos,
which still produces a compact spec.

Light spec files can be created manually, or sourced from a GitHub issue by passing a bare number to `/analyze-issue` or `/letsgo`. A purely numeric first argument to those two commands is always a GitHub issue reference.

At project scope, `/brainstorm <notion-url>` is the front end: it turns a Notion project brief into an aligned vision and publishes the work as light GitHub issues on a Project board. Those issues then become the light specs that `/analyze-issue <N>` and `/letsgo <N>` consume. `/brainstorm` accepts a Notion URL only — it does not take a KEY, a file path, or an issue number.

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

## Rule 9 — Engram: Save Progress, Not Just Files

Agents use Engram MCP tools (`mem_save`, `mem_update`, `mem_session_summary`)
for progress tracking by default. Markdown files remain for git-tracked
contracts (specs, decisions, commands, agents, skills).

### When to call Engram tools

- **After every sub-task**: `mem_save` with `topic_key: "impl/ISSUE_KEY/progress"`, `scope: project`
- **After every loop pass**: `mem_update` with `topic_key: "loop/ISSUE_KEY/passes"`, `scope: project`
- **On decisions**: `mem_save` with `topic_key: "decision/ISSUE_KEY/<slug>"`, `scope: global` (alongside `decisions.md` append)
- **On session end**: `mem_session_summary` with Goal/Instructions/Discoveries/Accomplished/Next Steps/Relevant Files
- **On errors**: `mem_save` with `topic_key: "impl/ISSUE_KEY/errors"`, `scope: project`

### Fallback

If Engram MCP is unavailable or returns an error, fall back to Markdown writes
in `specs/issue-{KEY}-progress.md`. Log the error and continue — do not crash.

### Scope conventions

- `project` (default): Issue-specific progress, test results, errors
- `global`: Cross-issue decisions that benefit other teams/sessions
- `personal`: User preferences (rarely used)

### Topic key convention

Always include ISSUE_KEY prefix: `impl/FEAT-123/progress`, not just `progress`.
This prevents collisions across different issues.

## Rule 10 — Engram: Search Before Assuming

Before working on something that might have been done before, call
`mem_search` with keywords from the task. Past sessions may contain decisions,
bug fixes, or patterns that save time.

When the user asks to recall something, search memory first (`mem_context` for
recent sessions, `mem_search` for keyword search) before guessing or re-deriving.
