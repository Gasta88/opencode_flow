---
description: Generate a full implementation spec from a light spec file. Add --quick for bugs and minor changes.
agent: build
model: opencode/qwen3.5-plus
---

# Analyze Issue: $ARGUMENTS

You are dispatching a spec-analysis task. Do not analyse the issue yourself —
delegate to a subagent.

## Step 1 — Parse arguments

`$ARGUMENTS` contains a path to a light spec file, optionally followed by `--quick`.

Extract:
- **FILE_PATH**: the first token (e.g. `specs/FEAT-123.md`)
- **ISSUE_KEY**: the basename of FILE_PATH without the `.md` extension
  (e.g. `specs/FEAT-123.md` → `FEAT-123`).
  If the derived ISSUE_KEY starts with `issue-`, strip that prefix
  (e.g. `issue-FEAT-123` → `FEAT-123`). Strip only the first occurrence
  (e.g. `issue-issue-FOO` → `issue-FOO`).
- **QUICK_MODE**: `true` if `--quick` appears anywhere in `$ARGUMENTS`, else `false`

## Step 1.5 — GitHub issue detection & materialize

If the first token of `$ARGUMENTS` matches `^[0-9]+$`, treat it as a GitHub
issue number instead of a file path.

**Detection:**
- Extract **ISSUE_NUMBER** from the first token.
- Set **ISSUE_KEY** = ISSUE_NUMBER (as a string).
- Set **FILE_PATH** = `specs/{ISSUE_KEY}.md`.

**Fetch:**
Run:
```bash
gh issue view <ISSUE_NUMBER> --json number,title,body,url,state
```
- If `gh` is not authenticated or the call fails, stop and print:
```
❌ Could not fetch GitHub issue #<ISSUE_NUMBER>. Run `gh auth login` or verify the issue exists.
```
- If `state` is `CLOSED`, print a non-blocking warning and continue:
```
⚠️  GitHub issue #<ISSUE_NUMBER> is closed. Proceeding anyway.
```

**Materialize:**
- If `FILE_PATH` already exists on disk, use it as-is (do not overwrite) and
  proceed to Step 2.
- If `FILE_PATH` does not exist, write it:
```markdown
# {ISSUE_KEY}

<!-- Source: GitHub Issue #{ISSUE_KEY} — {url} -->

## Title
{issue title}

## Body
{issue body, verbatim}
```
Then proceed to Step 2.

If the first token does NOT match `^[0-9]+$`, skip this step entirely and
proceed to Step 2 with the existing FILE_PATH and ISSUE_KEY from Step 1.

## Step 2 — Verify the file exists

Check that FILE_PATH exists and is readable. If not, stop and print:
```
❌ File not found: <FILE_PATH>
```

## Step 3 — Delegate

If QUICK_MODE is `true`, invoke `@spec-analyst-quick` with this exact task:

> Generate a fast-path spec for issue **{ISSUE_KEY}**, reading the light spec file
> at `{FILE_PATH}`. Store all output files under `specs/`.
> Follow the spec-driven-workflow skill exactly.

If QUICK_MODE is `false`, invoke `@spec-analyst` with this exact task:

> Generate a full 6-phase implementation spec for issue **{ISSUE_KEY}**, reading
> the light spec file at `{FILE_PATH}`. Store all output files under `specs/`.
> Follow the spec-driven-workflow skill exactly.

## Step 4 — Report

After the subagent completes, print the paths of the three files it produced:
```
✅ Spec ready:
  - specs/issue-{ISSUE_KEY}-findings.md
  - specs/issue-{ISSUE_KEY}-progress.md
  - specs/issue-{ISSUE_KEY}-spec.md
```
