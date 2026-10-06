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

## 2026-10-06 — /letsgo automation hardening for AI Software Factory

Issue: Auto OpenCode Flow v1 design (Notion)
Decision: `/letsgo` receives six new flags: `--headless` (converts all human prompts to structured stops), `--strict-tests` (test failures after fix budget stop the pipeline; default true under headless), `--make-ci` (requires `make ci` target as the test gate), `--spec-confidence N` (escalate only conflicts with confidence >= N), `--no-auto-commit` (existing). Feature branch is created in Step 0.1 before any implementation runs. Post-review test re-run catches regressions from code-fixer changes. `specs/` files excluded from `git add` during PR creation. Agent allow-lists updated: `make *` added to `spec-implementer` and `dod-evaluator`. Models upgraded: `spec-conflict-checker` and `code-reviewer` moved from deepseek-v4.1-flash to qwen3.8-flash.
Rationale: Real /letsgo runs across venovate-vmg2 (10+ pipeline executions) revealed blocking human prompts preventing unattended operation, test gate not blocking PRs, branch created too late (main contamination risk), code-fixer changes never re-tested, spec checker producing false positives on cheap model, and make commands blocked by permission rules. These changes enable scheduled, headless pipeline runs for an AI Software Factory.
Alternatives considered: (1) External driver script for control flow — deferred to v2; the command-level approach is simpler for now. (2) Remote CI loop with fix agent — out of scope for command; belongs in a driver/scheduler layer. (3) Strict tests always on by default — rejected; breaks existing workflows that rely on the advisory gate.
Scope: repo-wide — affects `letsgo.md`, all agent files, `SKILL.md`
-->
