---
description: Implement code changes from an existing spec file, working the Implementation Plan as a task graph with optional parallel frontier dispatch
argument-hint: <ISSUE_KEY> [--max-parallel N]
agent: build
model: opencode/qwen3.5-plus
---

# Implement Spec: $ARGUMENTS

Dispatch an implementation task. Do not write code yourself — delegate to `@spec-implementer`.

## Step 0 — Parse arguments

**ISSUE_KEY**: first token. **MAX_PARALLEL**: integer after `--max-parallel`, default `2`; `1` = strictly sequential (one implementer at a time, in `Depends On` order).

## Step 1 — Locate the spec

Require `specs/issue-ISSUE_KEY-spec.md` and `specs/issue-ISSUE_KEY-progress.md`. Missing → stop:
```
❌ Spec not found for ISSUE_KEY. Run /analyze-issue first.
```

## Step 2 — Sanity-check the spec is complete

In `progress.md`, every `- [ ]`/`- [x]` line under `## Phases` must be `[x]`. Else stop:
```
❌ Spec for ISSUE_KEY is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

## Step 2.3 — Human review gate

If `progress.md` contains `MODE: quick`, skip. Otherwise require a `## Human Review` section with `- [x] Approved by user on <date>`. Else stop:
```
❌ Spec for ISSUE_KEY has not been human-reviewed.
   Run /review-spec ISSUE_KEY first.
```

## Step 2.5 — Fetch external documentation

Invoke `@external-scout`:
> Fetch external dependency docs for issue **ISSUE_KEY**.
> Spec: `specs/issue-ISSUE_KEY-spec.md`

`NO_EXTERNAL_DEPS` → Step 3. Otherwise `specs/issue-ISSUE_KEY-extdocs.md` is written and the implementer reads it automatically.

## Step 3 — Parse the task graph

Read `## Implementation Plan`. Each row is a node with `#`, `Depends On` (blocking edges or `—`), and `Files` (declared set when present).

Cross-reference `progress.md` (and Engram `impl/ISSUE_KEY/progress`): a sub-task checked with an `Evidence:` line is **done**. The **frontier** is every sub-task whose `Depends On` are all done and which is not itself done.

No `Depends On` info, or MAX_PARALLEL = `1` → linear chain; dispatch one implementer for the whole plan:
> Implement issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Track progress. Follow the skill exactly.

Then go to Step 4.

## Step 3.5 — Frontier waves (MAX_PARALLEL > 1)

Repeat while any sub-task remains not done:

1. Compute the frontier.
2. **Disjointness guard**: select up to MAX_PARALLEL frontier sub-tasks whose declared `Files` sets do not intersect. A sub-task with no declared set, or one intersecting another member's, is deferred to a later wave (run it sequentially this wave only if it is the sole selectable task). Two sub-tasks touching the same file never share a wave.
3. Dispatch one `@spec-implementer` per selected sub-task — **all invocations in a single message** so they run concurrently — each with:
> Implement **only sub-task N** of issue **ISSUE_KEY** from `specs/issue-ISSUE_KEY-spec.md`. Touch only the files declared for sub-task N. Other sub-tasks are being implemented concurrently by other agents — do not modify their files, do not commit their work, and do not mark any other sub-task complete. Track progress under Engram topic_key `impl/ISSUE_KEY/subtask-N` (fallback: append only sub-task N's line to progress.md). Follow the skill exactly.
4. After the wave completes, update `progress.md` from the per-sub-task evidence (check off completed sub-tasks, copy Evidence lines), recompute the frontier, and repeat.
5. If a wave reports a failure or 3-strike escalation on any sub-task, stop dispatching new waves and surface the escalation.

## Step 4 — Report

```
✅ Implementation complete for ISSUE_KEY.
   See specs/issue-ISSUE_KEY-progress.md for the trail.
```
