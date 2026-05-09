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

### Commands (`commands/`)

User-invokable workflows that orchestrate agents:

| Command | Description |
|---------|-------------|
| `/analyze-issue <path>` | Generate an implementation spec from a light spec file (add `--quick` for minor changes) |
| `/implement-spec <KEY>` | Execute code changes from a completed spec |
| `/review-code` | Run adversarial code review on the current git diff |
| `/create-pr "<title>"` | Create a PR with a structured description, auto-generated from the diff |
| `/handover` | Generate a comprehensive handover document for async collaboration |

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
    ↓  /implement-spec FEAT-123
Code changes + tests                     ← spec re-read before every file edit
    ↓  /review-code                      ← adversarial review (optional)
    ↓  /create-pr "<title>"
PR
```

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
- **Spec as attention anchor** — The spec is re-read before every file edit during implementation
- **Progress is always current** — Every phase and error is logged in real-time to `progress.md`
- **Adversarial review** — Code is reviewed by a critical AI, then filtered by a meta-reviewer to surface only high-signal findings

## Getting Started

1. Install [OpenCode](https://opencode.ai)
2. Copy this repository's contents into your OpenCode configuration directory
3. Create a light spec file (e.g., `specs/FEAT-123.md`) describing the change you want
4. Run `/analyze-issue specs/FEAT-123.md` to generate a full implementation spec
5. Run `/implement-spec FEAT-123` to execute the changes
6. Run `/review-code` to get an adversarial review of your diff
7. Run `/create-pr "Your PR title"` to open a pull request

## License

[Add your license here]
