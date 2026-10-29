# OpenCode Flow

A structured, spec-driven AI development workflow for OpenCode — an interactive CLI coding assistant. This repository provides custom agents, commands, and a skill that together enable a disciplined engineering process: from light spec files to implementation, adversarial code review, PR creation, and async handovers.

## Overview

OpenCode Flow enforces a **spec-before-code** methodology. Instead of jumping straight into implementation, every change starts as a light spec file that gets analyzed, structured into a full implementation plan, and then executed by specialized AI subagents. The workflow is designed to reduce hallucination, maintain context across sessions, and produce high-quality, reviewable code.

## Architecture

### Agents (`agents/`)
Specialized AI subagents: `spec-analyst` / `spec-analyst-quick` (spec generation), `spec-implementer` (implementation, red-green TDD at declared seams), `code-reviewer` (bugs axis) / `standards-reviewer` (standards axis) / `spec-fidelity-reviewer` (spec axis) / `code-review-filter` / `code-fixer` (three-axis review + remediation), `dod-evaluator` (DoD gate), `spec-conflict-checker` (pre-flight checks), `external-scout` (dependency docs).

### Commands (`commands/`)
User-invokable workflows: `/brainstorm` (Notion brief → aligned vision → light GitHub issues on a Project board, routed to the Foundry or the human lane), `/analyze-issue` (spec generation, add `--quick` for minor changes), `/review-spec` (human approval gate, skipped for `--quick`), `/implement-spec` (task-graph implementation with parallel frontier waves via `--max-parallel`), `/implement-loop` (DoD-gated loop, full specs only), `/review-code` (three-axis review — bugs / standards / spec fidelity — + fix loop), `/create-pr` (structured PR: Summary visual, Evidence, Merge Danger), `/handover` (async handover doc), `/retro` (post-session environment audit), `/letsgo` (full pipeline end-to-end).

### Skills (`skills/`)
`spec-driven-workflow`: 3-file persistence pattern, spec lifecycle rules, decision escalation.
`debugging-and-error-recovery`: six-phase diagnosis loop (feedback loop first), stop-the-line, 3-strike escalation.

## Workflow

**Project pipeline (`/brainstorm`):**
```
Notion brief → /brainstorm → grilling rounds → vertical slices → Foundry/human routing → GitHub issues + primed Project board
```
Each issue is deliberately light — user story, goal, constraints, acceptance criteria, and a `## Foundry fit` block only. `Ready` is reserved for slices that are Foundry-fit, unblocked, have all prerequisites met, and were confirmed by the user; every other slice starts in the board's intake status. The deep specification is generated per issue later, on demand, by `/analyze-issue <N>` or `/letsgo <N>`. Run `/letsgo` on human-lane issues; the Foundry picks up the `Ready` queue.

**Manual pipeline:**
```
Light Spec → /analyze-issue → [spec files] → /review-spec → /implement-spec or /implement-loop → Code + tests → /review-code → /create-pr → PR
```

**One-shot (`/letsgo`):** runs the entire pipeline end-to-end:
```
1. Analyze → 2. Auto-resolve spec conflicts (human escalation if unresolved after 3 turns) → 3. Implement (DoD loop for full specs) → 4. Test gate → 5. Adversarial review + remediation loop → 6. PR
```
A human is only interrupted when automation cannot resolve something — unresolved spec conflicts, critical DoD failures, or residual review findings. See `commands/letsgo.md` for details.

**Foundry mode (`/letsgo <N> --headless --base <branch> [--quick] [--merge-mode auto|direct]`):** when BOTH `--headless` and `--base` are present, `/letsgo` runs the Code Foundry lifecycle end-to-end: a fail-closed preflight on the live issue body (`## Foundry fit` must say `Fit: yes`; `## Blocked by` refs resolve against GitHub state or same-repo board `Integrated`), a Project board claim (`In Progress`) before any branch/commit/push, a `feat/<N>-<14-digit-timestamp>` branch from `origin/<base>` with resume-detection (never a second PR), a draft-PR mutex created before the first implementation commit, scan-before-every-push checkpoint pushes (never force), and a land path that updates the PR body, marks it ready, and merges with exactly one strategy (`--merge-mode auto` arms `--auto --merge`; `direct` runs `--merge`). Every exit writes the frozen-schema `result.json` and upserts a single `<!-- opencode-flow:result -->` marker comment; any post-mutex stop closes the PR and marks the issue `Blocked`. The board's `Integrated` status and merge truth belong to the host reconciler. Verify with `bash tests/verify-letsgo-foundry.sh && bash tests/verify-letsgo-base.sh && bash tests/verify-letsgo-result.sh`.

## The 3-File Pattern

Every issue generates exactly three files in `specs/`:

| File | Purpose |
|------|---------|
| `issue-{KEY}-findings.md` | Verbatim light spec content + raw codebase notes |
| `issue-{KEY}-progress.md` | Phase checkboxes, implementation progress, and error log |
| `issue-{KEY}-spec.md` | Structured implementation spec with requirements, technical details, test strategy, and definition of done |

## Getting Started

1. Install [OpenCode](https://opencode.ai)
2. Copy this repository's contents into your OpenCode configuration directory
3. Add `specs/*-extdocs.md` to `.gitignore`
4. Start a project with `/brainstorm <notion-url>`, or create a light spec (e.g. `specs/FEAT-123.md`), or pass a GitHub issue number directly
5. Run `/analyze-issue specs/FEAT-123.md` (or `/letsgo 123` for the full pipeline)

### Notion Projects

`/brainstorm <notion-url>` reads a Notion project brief, interviews you in rounds until the vision is unambiguous, breaks it into vertical slices, routes each slice to the Foundry or the human lane, and publishes it as a light GitHub issue on a Project board — creating and linking the board if the repository has none. Requires the Notion MCP server and `gh auth login` with the `project` scope. The vision and its rationale persist to Engram when available; the command writes no files under `specs/`. Foundry-fit issues are self-contained (a short vision excerpt is inlined in `## Context`) because the Foundry sandbox cannot reach Engram. `Ready` is set only for confirmed, unblocked, `Fit: yes` slices; all others land in the intake status. Run `/letsgo <N>` on human-lane issues, and let the Foundry pick up the `Ready` queue.

### GitHub Issue Numbers

Pass a bare number to `/analyze-issue` or `/letsgo` (e.g. `/letsgo 123`). The command fetches the issue via `gh` CLI and materializes it as `specs/123.md`. Requires `gh auth login`. A numeric first argument is always a GitHub issue, never a manual KEY. `/brainstorm` does not take a number — it takes a Notion URL. See `AGENTS.md` Rule 1 for details.

