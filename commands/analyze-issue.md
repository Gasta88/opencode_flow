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
  (e.g. `specs/FEAT-123.md` → `FEAT-123`)
- **QUICK_MODE**: `true` if `--quick` appears anywhere in `$ARGUMENTS`, else `false`

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
