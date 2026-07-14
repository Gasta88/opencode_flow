# OpenCode Flow

A structured, spec-driven AI development workflow for OpenCode — an interactive CLI coding assistant. This repository provides custom agents, commands, and a skill that together enable a disciplined engineering process: from light spec files to implementation, adversarial code review, PR creation, and async handovers.

## Overview

OpenCode Flow enforces a **spec-before-code** methodology. Instead of jumping straight into implementation, every change starts as a light spec file that gets analyzed, structured into a full implementation plan, and then executed by specialized AI subagents. The workflow is designed to reduce hallucination, maintain context across sessions, and produce high-quality, reviewable code.

## Architecture

The project is organized into three core components:

### Agents (`agents/`)

Specialized AI subagents with distinct roles:

| Agent | Model | Purpose |
|-------|-------|---------|
| `spec-analyst` | qwen3.6-plus | Generates full 6-phase implementation specs from light spec files |
| `spec-analyst-quick` | qwen3.5-plus | Fast-path 2-phase specs for bugs, typos, and minor changes |
| `spec-implementer` | qwen3.6-plus | Implements code from specs, tracking progress and tests |
| `code-reviewer` | kimi-k2.5 | Adversarial code reviewer — finds bugs, logic errors, and security issues |
| `code-review-filter` | qwen3.5-plus | Meta-reviewer that filters false positives and nitpicks from review output |
| `spec-conflict-checker` | qwen3.5-plus | Binary CLEAR/CONFLICTS verdict on a spec vs `decisions.md` and the codebase — used by `/letsgo` |

### Commands (`commands/`)

User-invokable workflows that orchestrate agents:

| Command | Description |
|---------|-------------|
| `/analyze-issue <path>` | Generate an implementation spec from a light spec file (add `--quick` for minor changes) |
| `/review-spec <KEY>` | Human-gated review of a generated spec before implementation (skipped for `--quick`) |
| `/implement-spec <KEY>` | Execute code changes from a completed spec (works with both quick and full specs) |
| `/implement-loop <KEY>` | Implement a spec and loop until DoD is satisfied (requires full spec, not `--quick`) |
| `/review-code` | Run adversarial code review on the current git diff |
| `/create-pr "<title>"` | Create a PR with a structured description, auto-generated from the diff |
| `/handover` | Generate a comprehensive handover document for async collaboration |
| `/letsgo <path> [--quick] [--max-spec-turns N] [--max-impl-passes N] [--max-fix-passes N]` | Run the entire pipeline end-to-end: analyze → auto-resolve spec conflicts (escalating to a human only if unresolved) → implement → adversarial review with a fix loop → PR |

### Skills (`skills/`)

| Skill | Purpose |
|-------|---------|
| `spec-driven-workflow` | Defines the 3-file persistence pattern and spec lifecycle rules |

## Workflow

```
Light Spec File
    ↓  /analyze-issue FEAT-123           (or --quick for small issues)
specs/issue-FEAT-123-findings.md         ← raw file data
specs/issue-FEAT-123-progress.md         ← phase tracking
specs/issue-FEAT-123-spec.md             ← structured spec
    ↓  /review-spec FEAT-123             (human approval gate; skipped for --quick)
    ↓  /implement-spec FEAT-123          (quick specs: single pass)
    ↓  /implement-loop FEAT-123          (full specs: loop until DoD met)
Code changes + tests                     ← spec re-read before every file edit
    ↓  /review-code                      ← adversarial review (optional)
    ↓  /create-pr "<title>"
PR
```

**Note:** Use `/review-spec` to approve full-mode specs before implementation. Quick-mode specs (`--quick`) skip this gate. Use `/implement-spec` for `--quick` specs (bugs, minor changes). Use `/implement-loop` for full specs that have a `## Definition of Done` section and need iterative evaluation.

### One-shot pipeline: `/letsgo`

`/letsgo specs/FEAT-123.md` runs the whole thing above end-to-end in a single
command, with automated gates in place of manual command-by-command driving:

```
Light Spec File
    ↓  /letsgo specs/FEAT-123.md
1. Analyze issue                → spec-analyst / spec-analyst-quick
2. Auto-resolve spec conflicts  → spec-conflict-checker + spec-analyst, up to 3 turns
     ↳ still unresolved?        → escalate to a real human (approve/request-changes/reject)
3. Implement                    → spec-implementer (+ dod-evaluator loop for full specs)
4. Adversarial code review      → code-reviewer + code-review-filter
5. Remediate findings           → spec-implementer fixes, re-review, up to 3 passes
     ↳ still unresolved?        → ask the human whether to continue or stop
6. Create PR                    → title auto-derived from the spec
PR
```

A real human is only interrupted when automation genuinely cannot resolve
something — an unresolved spec conflict after 3 turns, an unmet DoD after the
implementation pass budget, or residual code review findings after the fix
budget. See `commands/letsgo.md` for the full step-by-step logic.

## The 3-File Pattern

Every issue generates exactly three files in `specs/`:

| File | Purpose |
|------|---------|
| `issue-{KEY}-findings.md` | Verbatim light spec content + raw codebase notes |
| `issue-{KEY}-progress.md` | Phase checkboxes, implementation progress, and error log |
| `issue-{KEY}-spec.md` | Structured implementation spec with requirements, technical details, test strategy, and definition of done |

## Core Principles

- **Data before analysis** — Raw spec data is persisted immediately before any reasoning
- **Spec before code** — Implementation never starts without a complete spec
- **Human review before implementation** — Full-mode specs require explicit human approval via `/review-spec` before any code is written; quick-mode specs are exempt
- **Spec as attention anchor** — The spec governs all implementation decisions
- **Progress is always current** — Every phase and error is logged in real-time to `progress.md`
- **Adversarial review** — Code is reviewed by a critical AI, then filtered by a meta-reviewer to surface only high-signal findings

## Getting Started

1. Install [OpenCode](https://opencode.ai)
2. Copy this repository's contents into your OpenCode configuration directory
3. **Setup `.gitignore`**: Add `specs/*-extdocs.md` to your project's `.gitignore`. These files are working artefacts generated by the `external-scout` agent and should never be committed.
4. Create a light spec file (e.g., `specs/FEAT-123.md`) describing the change you want
5. Run `/analyze-issue specs/FEAT-123.md` to generate a full implementation spec
6. Run `/review-spec FEAT-123` to review and approve the spec (skipped for `--quick` specs)
7. Run `/implement-spec FEAT-123` to execute the changes
8. Run `/review-code` to get an adversarial review of your diff
9. Run `/create-pr "Your PR title"` to open a pull request

Or run the whole thing in one command: `/letsgo specs/FEAT-123.md`.

