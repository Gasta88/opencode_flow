---
description: Human-gated review of a generated spec before implementation begins
argument-hint: <ISSUE_KEY> [--visual]
agent: build
model: opencode/qwen3.6-plus
---

# Review Spec: $ARGUMENTS

Human-gated review dispatcher. Do not write implementation code — present the spec, collect the user's decision, and act accordingly.

## Step 1 — Parse arguments

**ISSUE_KEY**: first token. **--visual**: present if the flag appears.

## Step 2 — Locate the spec

Require `specs/issue-ISSUE_KEY-spec.md` and `specs/issue-ISSUE_KEY-progress.md`. Missing → stop:
```
❌ Spec not found for ISSUE_KEY. Run /analyze-issue first.
```

## Step 2.1 — Detect quick-mode

If `progress.md` contains `MODE: quick`, stop:
```
ℹ️  ISSUE_KEY is a quick-mode spec. Quick specs skip the human review gate.
   Run /implement-spec ISSUE_KEY to proceed directly.
```

## Step 2.2 — Verify phase completion

Every `- [ ]`/`- [x]` line under `## Phases` must be `[x]`. Else stop:
```
❌ Spec for ISSUE_KEY is incomplete. Re-run /analyze-issue.
Unfinished phases: <list>
```

## Step 3 — Present the spec

Read `specs/issue-ISSUE_KEY-spec.md` in full. With `--visual`, render as HTML with the Implementation Plan as an interactive checklist (fall back to text if unavailable). Otherwise present section by section: Requirements, Technical Specification, Implementation Plan, Test Strategy, Definition of Done.

## Step 4 — Prompt for decision

```
How would you like to proceed?
  [A] Approve as-is
  [R] Request changes
  [J] Reject
```

## Step 5a — On approval

`mem_update` with `topic_key: "review/ISSUE_KEY/human-approval"`, `title: "Human Review — Approved for ISSUE_KEY"`, `type: manual`, `scope: project`, content What/Why/Where/Learned.

If Engram is unavailable, append to `progress.md`:
```markdown
## Human Review
- [x] Approved by user on <YYYY-MM-DD>
```

Print:
```
✅ Spec approved for ISSUE_KEY. Ready for /implement-spec or /implement-loop.
```

## Step 5b — On request changes

1. Collect free-text feedback; if empty, re-prompt.
2. Re-invoke `@spec-analyst`:
```
Revise the spec for issue ISSUE_KEY based on the following feedback.
Existing spec: specs/issue-ISSUE_KEY-spec.md
Existing progress: specs/issue-ISSUE_KEY-progress.md
Feedback: <user feedback>
Regenerate only the affected sections. Do not discard Phase 1–2 work.
Update progress.md to reflect which phases were re-done.
```
3. Present only the changed sections with a summary, then re-prompt (Step 4).

## Step 5c — On rejection

Do NOT delete any files; leave them as an audit trail. Print:
```
⚠️  Spec for ISSUE_KEY has been rejected. Files remain on disk as audit trail. Run /analyze-issue to start fresh if needed.
```
Stop.
