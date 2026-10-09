# OpenCode Flow

A structured, spec-driven AI development workflow for OpenCode — an interactive CLI coding assistant. This repository provides custom agents, commands, and a skill that together enable a disciplined engineering process: from light spec files to implementation, adversarial code review, PR creation, and async handovers.

## Overview

OpenCode Flow enforces a **spec-before-code** methodology. Instead of jumping straight into implementation, every change starts as a light spec file that gets analyzed, structured into a full implementation plan, and then executed by specialized AI subagents. The workflow is designed to reduce hallucination, maintain context across sessions, and produce high-quality, reviewable code.

## Architecture

### Agents (`agents/`)
Specialized AI subagents: `spec-analyst` / `spec-analyst-quick` (spec generation), `spec-implementer` (implementation), `code-reviewer` / `code-review-filter` / `code-fixer` (review + remediation), `dod-evaluator` (DoD gate), `spec-conflict-checker` (pre-flight checks), `external-scout` (dependency docs).

### Commands (`commands/`)
User-invokable workflows: `/brainstorm` (Notion brief → aligned vision → light GitHub issues on a Project board), `/analyze-issue` (spec generation, add `--quick` for minor changes), `/review-spec` (human approval gate, skipped for `--quick`), `/implement-spec` (single-pass implementation), `/implement-loop` (DoD-gated loop, full specs only), `/review-code` (adversarial review + fix loop), `/create-pr` (structured PR), `/handover` (async handover doc), `/letsgo` (full pipeline end-to-end).

### Skills (`skills/`)
`spec-driven-workflow`: 3-file persistence pattern, spec lifecycle rules, decision escalation.

## Workflow

**Project pipeline (`/brainstorm`):**
```
Notion brief → /brainstorm → grilling rounds → vertical slices → GitHub issues + Project board
```
Each issue is deliberately light — user story, goal, constraints, and acceptance criteria only. The deep specification is generated per issue later, on demand, by `/analyze-issue <N>` or `/letsgo <N>`.

**Manual pipeline:**
```
Light Spec → /analyze-issue → [spec files] → /review-spec → /implement-spec or /implement-loop → Code + tests → /review-code → /create-pr → PR
```

**One-shot (`/letsgo`):** runs the entire pipeline end-to-end:
```
1. Analyze → 2. Auto-resolve spec conflicts (human escalation if unresolved after 3 turns) → 3. Implement (DoD loop for full specs) → 4. Test gate → 5. Adversarial review + remediation loop → 6. PR
```
A human is only interrupted when automation cannot resolve something — unresolved spec conflicts, critical DoD failures, or residual review findings. See `commands/letsgo.md` for details.

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

`/brainstorm <notion-url>` reads a Notion project brief, interviews you in rounds until the vision is unambiguous, breaks it into vertical slices, and publishes each slice as a light GitHub issue on a Project board — creating and linking the board if the repository has none. Requires the Notion MCP server and `gh auth login` with the `project` scope. The vision and its rationale persist to Engram; the command writes no files under `specs/`. Each issue stays light, so `/letsgo <N>` on any unblocked issue is the natural next step.

### GitHub Issue Numbers

Pass a bare number to `/analyze-issue` or `/letsgo` (e.g. `/letsgo 123`). The command fetches the issue via `gh` CLI and materializes it as `specs/123.md`. Requires `gh auth login`. A numeric first argument is always a GitHub issue, never a manual KEY. `/brainstorm` does not take a number — it takes a Notion URL. See `AGENTS.md` Rule 1 for details.

