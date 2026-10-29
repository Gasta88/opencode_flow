---
description: Generate a full implementation spec from a light spec file. Add --quick for bugs and minor changes.
agent: build
model: opencode/qwen3.5-plus
---

# Analyze Issue: $ARGUMENTS

Dispatch a spec-analysis task. Do not analyse the issue yourself — delegate to a subagent.

## Step 1 — Parse arguments

- **FILE_PATH**: first token (e.g. `specs/FEAT-123.md`).
- **ISSUE_KEY**: basename without `.md`; strip one leading `issue-` (`issue-FEAT-123` → `FEAT-123`; `issue-issue-FOO` → `issue-FOO`).
- **QUICK_MODE**: `true` if `--quick` appears anywhere, else `false`.

## Step 1.5 — GitHub issue detection & materialize

If the first token matches `^[0-9]+$`, treat it as a GitHub issue:
- **ISSUE_NUMBER** = first token; **ISSUE_KEY** = its string; **FILE_PATH** = `specs/{ISSUE_KEY}.md`.

```bash
gh issue view <ISSUE_NUMBER> --json number,title,body,url,state
```
Fetch failure → stop:
```
❌ Could not fetch GitHub issue #<ISSUE_NUMBER>. Run `gh auth login` or verify the issue exists.
```
`state == CLOSED` → non-blocking warning, continue:
```
⚠️  GitHub issue #<ISSUE_NUMBER> is closed. Proceeding anyway.
```

Materialize:
- `FILE_PATH` exists → use as-is (do not overwrite), go to Step 2.
- Else write:
```markdown
# {ISSUE_KEY}

<!-- Source: GitHub Issue #{ISSUE_KEY} — {url} -->

## Title
{issue title}

## Body
{issue body, verbatim}
```
Then Step 2.

A non-numeric first token skips this step.

## Step 2 — Verify the file exists

Missing or unreadable → stop:
```
❌ File not found: <FILE_PATH>
```

## Step 3 — Delegate

QUICK_MODE `true` → `@spec-analyst-quick`:
> Generate a fast-path spec for issue **{ISSUE_KEY}**, reading the light spec file at `{FILE_PATH}`. Store all output files under `specs/`. Follow the spec-driven-workflow skill exactly.

Otherwise → `@spec-analyst`:
> Generate a full 6-phase implementation spec for issue **{ISSUE_KEY}**, reading the light spec file at `{FILE_PATH}`. Store all output files under `specs/`. Follow the spec-driven-workflow skill exactly.

## Step 4 — Report

```
✅ Spec ready:
  - specs/issue-{ISSUE_KEY}-findings.md
  - specs/issue-{ISSUE_KEY}-progress.md
  - specs/issue-{ISSUE_KEY}-spec.md
```
