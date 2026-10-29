# Architectural Decisions

<!--
Format per entry:
## <YYYY-MM-DD> — <short title>
Issue: <ISSUE-KEY>
Decision: <ruling>
Rationale: <why>
Alternatives considered: <rejected options>
Scope: <repo-wide | subsystem | files>
-->

## 2026-08-11 — Numeric first argument always means GitHub issue number

Issue: 3b972d662ff3806793d4ebabb9ce8df8
Decision: A purely numeric first argument to `/brainstorm`, `/analyze-issue`, or `/letsgo` is a GitHub issue number, not a manual KEY. The command fetches it with `gh issue view` and materializes `specs/{NUMBER}.md`.
Rationale: Issues become the entry point; no manual light-spec file needed.
Alternatives considered: (1) `--issue` flag — rejected (minimal interface). (2) File-first lookup — rejected (ambiguous, silently overrides intent).
Scope: repo-wide; commands accepting a first KEY/FILE_PATH (`brainstorm.md`, `analyze-issue.md`, `letsgo.md`).

## 2026-10-06 — /letsgo automation hardening for AI Software Factory

Issue: Auto OpenCode Flow v1 design (Notion)
Decision: `/letsgo` gains `--headless` (prompts become structured stops), `--strict-tests` (default under headless), `--make-ci`, `--spec-confidence N`, and `--no-auto-commit`. The feature branch is created in Step 0.1 before implementation; a post-review test re-run catches code-fixer regressions; `specs/` is excluded from `git add`; `make *` is allowlisted for `spec-implementer`/`dod-evaluator`; `spec-conflict-checker` and `code-reviewer` move to `qwen3.8-flash`.
Rationale: 10+ real runs showed blocking prompts, late branch creation, untested fixes, false positives on a cheap model, and blocked `make` commands.
Alternatives considered: (1) External driver — deferred to v2. (2) Remote CI loop — out of scope. (3) Strict tests always on — rejected (breaks advisory workflows).
Scope: repo-wide — `letsgo.md`, agent files, `SKILL.md`.

## 2026-10-09 — /brainstorm is Notion-URL-only and project-scoped

Issue: Auto OpenCode Flow — Notion-to-issues front end
Decision: `/brainstorm` accepts **only** a Notion page URL and works at project scope. It fetches via the Notion MCP, grills in rounds over a design tree, cuts tracer-bullet vertical slices, quizzes the breakdown, then publishes light GitHub issues in dependency order onto a Project board. It writes **no** `specs/` files — the issues are the light specs. Vision/decisions/breakdown persist only to Engram (`vision/{PROJECT_SLUG}/{source,decisions,breakdown}`). Blocking edges are `## Blocked by` body text. The Project is discovered via `repository.projectsV2` every run (never cached); if absent, create and link in one `createProjectV2` mutation. **Supersedes 2026-08-11 for `brainstorm.md` only.**
Rationale: Projects start as briefs, not spec files; grilling closes misalignment before spec work; issues keep the deep-spec-on-demand contract.
Alternatives considered: separate command, `--project` flag, git-tracked vision file, native sub-issues, epic issue, cached project number, reusable grilling skill — all rejected (single entry point, shared contract, no extra permissions, no staleness).
Scope: `brainstorm.md`, `AGENTS.md` Rule 1, `README.md`, `skills/spec-driven-workflow/SKILL.md`.

## 2026-10-10 — /letsgo --base flag: ref-form contract and default-path freeze

Issue: 9
Decision: `--base <branch>` resolves once into `BASE_BRANCH` (bare, leading `origin/` stripped) and `BASE_REF` (`origin/<branch>`). Git plumbing (checkout, `merge-base`, diff/log) uses `BASE_REF`; `gh pr create --base` uses the bare `BASE_BRANCH`; branch-equality checks compare bare names. Omitting `--base` keeps the `origin/HEAD` derivation **byte-identical** (no fetch, no explicit start-point). The flag lives only in `/letsgo`; standalone `/review-code`, `/create-pr`, `/handover` keep their own derivations.
Rationale: `gh` misbehaves on `origin/<name>`; git needs the remote-tracking ref; unattended runs require a frozen default path.
Alternatives considered: (1) One variable stripped at each consumer — rejected (drift-prone). (2) Change the default path too — rejected (violates AC4). (3) Propagate the flag now — out of scope.
Scope: `commands/letsgo.md`; binds future `--base` propagation to the `symbolic-ref` idiom.

## 2026-10-10 — /letsgo result.json driver contract and every-exit invariant

Issue: 10
Decision: `/letsgo` writes `specs/issue-{ISSUE_KEY}-result.json` at **every** exit (E1–E17), including interactive stops. The schema is frozen to 7 fields (`issue`, `outcome`, `stage`, `reason`, `branch`, `pr_url`, `pipeline{spec_turns,impl_passes,fix_passes}`). Rulings: `issue` is a number for `^[0-9]+$`, else a string; `pipeline` is **absent** before Step 1; `branch`/`pr_url` are empty strings, never null; write-before-stop; last-run-wins; any future stop must carry a hook.
Rationale: The driver reads outcomes without logs; one missed exit yields `no_result`; freezing protects the external boundary.
Alternatives considered: (1) Headless-only hooks — rejected (Goal says every exit). (2) A test-fix counter — rejected (driver contract). (3) `stage="review"` for Step 7.5 — rejected (the failing gate is tests). (4) Plugin enforcement — deferred.
Scope: `commands/letsgo.md` + the auto-flow driver contract; binds every future exit point.

## 2026-10-19 — deepseek-v4.1-flash confirmed as the flash tier; extended to three more subagents

Issue: n/a (model-routing maintenance)
Decision: `opencode/deepseek-v4.1-flash` is the flash tier for mechanical subagents: `code-fixer`, `dod-evaluator`, `external-scout`, `code-review-filter`, `spec-analyst-quick` (temp 0.1). `deepseek-v4-flash` is **not** adopted. Reviewers/generators (`code-reviewer`, `spec-conflict-checker`, `spec-fidelity-reviewer`, `standards-reviewer`, `spec-analyst`, `spec-implementer`) stay on `qwen3.8-flash`; commands stay on the `qwen3.5/3.6-plus` tier. Applied to repo and global mirror.
Rationale: Flash fits mechanical, high-volume work; adversarial review stays on another vendor; orchestration keeps the plus tier.
Alternatives considered: adopt `v4-flash`, move reviewers to flash, move commands to flash, leave the three on qwen — all rejected.
Scope: `external-scout.md`, `code-review-filter.md`, `spec-analyst-quick.md` (+ mirrors); sets the model policy for future agents.

## 2026-10-28 — /brainstorm routes slices to the Foundry or the human lane

Issue: n/a (project-level brainstorm / Code Foundry integration)
Decision: `/brainstorm` classifies every slice with `## Foundry fit` (`Fit: yes|no`, `Why`, `Needs before Ready`, `Verification`) and primes Status after `item-add`. `Ready` = Fit yes AND blockers closed/Integrated AND all prerequisites satisfied AND user confirmed; everything else goes to intake (`Backlog`/`To Do`/`Todo`). Never set `Blocked`/`In Progress` at creation. `Fit` is a slice property; `Ready` is a board state. Foundry-fit bodies are self-contained with a `## Context` vision excerpt (sandbox cannot reach Engram). Use the real `PROJECT_OWNER`; provision/repair Status only with consent. No `foundry-fit` label. Extends 2026-10-09.
Rationale: The Foundry picks only `Ready` by board position and exact option names; `item-add` alone lands in the default.
Alternatives considered: Engram injection into sandbox (deferred), a `Human` status, auto-promotion, a label, strict `Fit: no` until CI exists — all rejected.
Scope: `brainstorm.md`, `AGENTS.md` Rule 1, `README.md`, `SKILL.md`; binds future `/brainstorm` changes.

## 2026-10-29 — /letsgo Foundry mode: activation gate, draft-PR mutex, land contract

Issue: 13
Decision: Foundry mode is active **only** when `--headless` AND `--base` are present; the interactive path is byte-identical. Lifecycle: fail-closed preflight on the live body (`Fit: yes`; refs only `#N`/`OWNER/REPO#N`; CLOSED/MERGED or same-repo OPEN `Status == Integrated`; exactly-one project) → claim `In Progress` before any branch/commit/push → branch `feat/<N>-<14-digit-ts>` from `origin/<base>` (never reuse a non-base branch; unique-match RESUME_CHECK) → draft-PR mutex (empty commit → sensitive scan → push → `gh pr create --draft`) → pipeline with scan-before-every-push → land via `gh pr edit` → conditional `gh pr ready` → exactly one strategy (`--auto --merge` or `--merge`). Every exit writes result.json (E18–E23, E17-F) and one marker comment; post-mutex stops close the PR and set `Blocked`. Never write `Integrated`, never squash/rebase, never retry with another strategy, never add `Closes #N`, bound every external call.
Rationale: The reconciler decides *when*, not *how*; needs a fail-closed gate, a crash-safe mutex, and safe re-entry; merge truth belongs to the reconciler.
Alternatives considered: squash/rebase, write `Integrated` after arming, reuse the non-base branch, terminal PR creation, shared surface now, new enums — rejected/deferred.
Scope: `letsgo.md`, `spec-implementer.md` push rule, `README.md`, `tests/verify-letsgo-foundry.sh`; binds exits, board writes, and the flag surface.

## 2026-10-29 — Shared Foundry surface is a skill (`foundry-headless-contract`)

Issue: 14
Decision: The canonical board + result-comment surface is a **skill** defining F1 project discovery (exactly-one, never cached, fail-closed), F2 status write (precheck → read → no-op or exact `item-edit`; never create/rename options; never `Ready`/`Integrated`), F3 idempotent marker-comment upsert (find→`-X PATCH`, else create; token hygiene; F1-independent), and F4 the `gh` allowlist — which **must include `gh api *`**. Consumers carry `Load skill: foundry-headless-contract` and no inline recipes; the harness pins load-line presence, recipe absence, and runs the recipes against a fake-`gh` shim. OD1: a consumer glob auto-covers `review-pr.md`. OD2: "zero comments" constrains the surface; command-level mirrors keep their hooks.
Rationale: Commands are LLM governors; `Load skill:` is the repo idiom; a hidden agent loses governor state; executable recipes are testable.
Alternatives considered: hidden agent, bash helper library, refactor `/brainstorm` onto the surface, narrow F4 to three families — all rejected.
Scope: `skills/foundry-headless-contract/` (+ mirror), `letsgo.md` load line, `tests/verify-foundry-surface.sh`, `tests/verify-letsgo-foundry.sh`; the sandbox image must ship the skill.

## 2026-10-29 — /review-pr repair loop: bucket polling, F3-comment verdict memoization, never-close ownership

Issue: 15
Decision: `commands/review-pr.md` repairs red Foundry PRs under three rulings. (1) Polling: classify by `gh pr checks --json name,bucket,link` `bucket` values, never the exit code; bound each cycle by `--deadline` (900 s, 60 s interval); `--watch` forbidden; pending-at-deadline is a non-terminal, non-memoized stop. (2) Memoization: terminal exhaustion verdicts live in the existing F3 comment — `reason` carries a `head <SHA>` token compared to `headRefOid`; no new artifact, no result.json write. (3) Ownership: never close, never retry a merge with another strategy, never write `Ready`/`Integrated`/`In Progress`; only `Blocked` via F2; leave the PR OPEN at exhaustion; if no linked issue resolves (branch `^feat/<N>-`, then body `Related Issues #N`), degrade to a zero-write summary. Reviewer/fixer dispatches carry no-commit/no-push; the governor creates exactly one commit per attempt.
Rationale: Repeated ticks would re-spend the budget without memoization; slow CI is misread as red by exit codes; `/review-pr` does not own the mutex; the 7-field vocabulary is frozen.
Alternatives considered: a separate state file, exit-code classification, subagent commits, invoking `/review-code`, closing at exhaustion — all rejected.
Scope: `commands/review-pr.md` + `tests/verify-review-pr.sh`; binds the reconciler tick semantics, future `gh pr checks` pollers, and the Foundry surface.
