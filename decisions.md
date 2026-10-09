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
-->

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

## 2026-10-09 — /brainstorm is Notion-URL-only and project-scoped

Issue: Auto OpenCode Flow — Notion-to-issues front end
Decision: `/brainstorm` now accepts **only** a Notion page URL and operates at project scope, not issue scope. It fetches the brief via the Notion MCP `fetch` tool, grills the user in rounds over a design tree until the frontier is empty, breaks the confirmed vision into tracer-bullet vertical slices, quizzes the user on the breakdown, then publishes each slice as a light GitHub issue in dependency order and places it on a Project board. It writes **no** files under `specs/` — the GitHub issues are the light specs, and `/analyze-issue <N>` / `/letsgo <N>` generate the deep spec per issue later. The vision, its settled decisions, and the slice breakdown persist to Engram only (`vision/{PROJECT_SLUG}/{source,decisions,breakdown}`, scope `project`). Blocking edges are expressed as `## Blocked by` text in the issue body, not as native sub-issues or a ProjectV2 custom field. The linked Project is detected via GraphQL `repository.projectsV2` on every run and never cached; when absent it is created and linked in a single `createProjectV2(input:{ownerId,title,repositoryId})` mutation. **This supersedes the 2026-08-11 ruling for `brainstorm.md` only** — `/analyze-issue` and `/letsgo` still treat a bare numeric first argument as a GitHub issue number.
Rationale: Projects start as Notion briefs, not as pre-written light spec files, so the workflow had no front end for turning a vision into trackable work. Grilling in rounds (whole frontier at once, each question carrying a recommended answer) closes the misalignment gap before any spec is written. Keeping issues light preserves the existing contract that deep specification is generated on demand, and closing the loop through issue numbers means `/letsgo <N>` already materializes `specs/<N>.md` with no new plumbing. `createProjectV2` accepts `repositoryId`, so create-and-link is one mutation rather than two calls.
Alternatives considered: (1) A separate `/brainstorm-project` command — rejected; the user wanted one entry point, and mode detection by input shape keeps the surface minimal. (2) A `--project` flag on `/brainstorm` — rejected as redundant once legacy input modes were dropped entirely. (3) A git-tracked `specs/{PROJECT}-vision.md` — rejected in favour of Engram-only; accepted trade-off is that the vision rationale is single-machine and invisible to a fresh clone, with the GitHub issues serving as the shared contract. (4) Native GitHub sub-issues via `addSubIssue`, or a ProjectV2 `Blocked by` custom field — rejected; body text needs no extra permissions and `/analyze-issue` inherits the dependency graph for free when it materializes the issue body. (5) An epic issue holding the vision — rejected; the board stays work-only. (6) Caching the Project number in a config file — rejected as a staleness risk for one cheap GraphQL call. (7) A reusable `skills/grilling/SKILL.md` — rejected; the protocol is inlined in `brainstorm.md` because subagents cannot converse with the user, so the interview cannot be delegated.
Scope: repo-wide — affects `brainstorm.md`, `AGENTS.md` Rule 1, `README.md`, `skills/spec-driven-workflow/SKILL.md`
