---
description: Retrospective on a coding session — suggest improvements to the agent environment (navigation, automated checks, standards, steering files, tooling), most severe first
argument-hint: <optional — session or issue key to retrospect on; defaults to the current session>
agent: build
model: opencode/qwen3.6-plus
---

# Retrospective: $ARGUMENTS

Suggest improvements to the coding agent's **environment**, not fixes to the session's code.

## Step 1 — Gather the session record

Target: an issue key → reconstruct that run; a described session/timeframe → use it; otherwise the current session.

Sources, first available wins (combine when several exist):
1. Engram: `mem_context`; `mem_search` for the key (`impl/ISSUE_KEY/{errors,progress}`, `pipeline/ISSUE_KEY/*`, `loop/ISSUE_KEY/passes`); `/brainstorm` → `vision/PROJECT_SLUG/*`.
2. `specs/issue-{KEY}-progress.md` — `## Errors`, loop passes, Evidence lines.
3. GitHub issues/PRs for the key (`gh issue view`, `gh pr view`).
4. `git log --oneline --since=...`.
5. Current conversation when this is the session.

## Step 2 — Improvement candidates

- **Navigation**: hard-to-find files or hidden dependencies → add a one-line pointer in AGENTS.md or a skill. Use when locating information was slow.
- **Automated checks**: read the repo's existing check command (`lint`/`check`/`test` targets, CI) first; a check that exists but is unwired or silently broken is the finding. A repo with no guardrail is itself a finding. Use when a mistake was catchable, or no guardrail exists.
- **Review rules**: new, removed, or clarified rule for a reviewer. Mechanical violations (banned API, import shape, file location) get a deterministic check — default to a check over prose. Reserve prose for judgement calls. Use when reviewers missed a mistake.
- **Steering files**: move instructions from AGENTS.md/skills/agents into standards or checks; look for no-ops that did not change behavior. Use when steering files are large or an instruction was ignored/redundant.
- **Tool economy**: expensive tool calls that could be streamlined; token-inefficient custom tooling. Use when a call was expensive.
- **Information access**: missing logs, read-only third-party access, external docs the agent guessed at. Use when crucial information was unavailable.
- **Workflow friction**: gates, budgets, or flags that misfired (unverifiable DoD item, wrong seam, early-exhausted budget). Use when the pipeline, not the code, was the bottleneck.

## Step 3 — Present candidates

Most severe first:
```
### <N>. <Category> — <one-line finding>
Evidence:   <what happened, quoted or cited>
Proposal:   <concrete change: file to edit, check to build, rule to add>
Cost:       <low | medium | high>
```
Do not apply anything. If the user approves a candidate recording an architectural ruling, append a dated block to `decisions.md` and mirror it via `mem_save` with `scope: global`.

## Reference

- Implementation carries the most context pressure (`@spec-implementer`); reviewers carry the least. Prefer adding standards to a reviewer over bloating the implementer.
- **AGENTS.md** (repo + global) rides in every context — use sparingly, mostly navigation pointers.
- **decisions.md** — dated rulings, consulted before specs; this repo has no CODING_STANDARDS.md, so judgement-call standards live in AGENTS.md rules and reviewer prompts.
- **skills/** — descriptions ride in every context; keep them sharp and bodies lean.
- **agents/** — review agents are the right home for standards enforcement.
- **specs/** — per-issue reference, pointed to by commands, never loaded wholesale.
