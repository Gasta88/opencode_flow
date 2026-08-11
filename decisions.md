# Architectural Decisions

<!--
This file persists architectural rulings across issues.
Format for each entry:

## <YYYY-MM-DD> — <short title>
Issue: <ISSUE-KEY>
Decision: <one paragraph>
Rationale: <why>
Alternatives considered: <what was rejected and why>
Scope: <repo-wide | subsystem-name | specific-files>

Only record decisions that a future spec-analyst on an unrelated issue
would benefit from knowing about.

## 2026-08-11 — Numeric first argument always means GitHub issue number

Issue: 3b972d662ff3806793d4ebabb9ce8df8
Decision: A purely numeric first argument passed to `/brainstorm`, `/analyze-issue`, or `/letsgo` is always interpreted as a GitHub issue number, not a manual KEY. The command fetches the issue via `gh issue view` and materializes it into `specs/{NUMBER}.md`.
Rationale: Simplifies the workflow by allowing developers to use GitHub Issues directly as the entry point for the spec-driven workflow, without needing to manually create light spec files first.
Alternatives considered: (1) Introduce a new flag like `--issue` to disambiguate — rejected to keep the interface minimal and because numeric-only keys are rare in practice. (2) Check if the numeric key corresponds to an existing file first — rejected because it would create ambiguous behavior and silently override user intent.
Scope: repo-wide — affects all commands that accept a first argument as a KEY or FILE_PATH (`brainstorm.md`, `analyze-issue.md`, `letsgo.md`)
-->
