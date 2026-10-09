---
description: Retrospective on a coding session — suggest improvements to the agent environment (navigation, automated checks, standards, steering files, tooling), most severe first
argument-hint: <optional — session or issue key to retrospect on; defaults to the current session>
agent: build
model: opencode/qwen3.6-plus
---

# Retrospective: $ARGUMENTS

The user has asked for a **retrospective**. You are suggesting improvements to
the coding agent's **environment** to improve future runs. You are not fixing
the code from the session — you are fixing the conditions the code was
produced under.

## Step 1 — Gather the session record

Determine the target session:

- If `$ARGUMENTS` names an issue key (e.g. `FEAT-123`), reconstruct that run.
- If `$ARGUMENTS` describes a session or timeframe, use that.
- Otherwise, default to the current session.

Read the primary sources, in this order (first available wins; combine when
several exist):

1. **Engram**: `mem_context` for recent sessions; `mem_search` for the issue
   key (`impl/ISSUE_KEY/errors`, `impl/ISSUE_KEY/progress`,
   `pipeline/ISSUE_KEY/*`, `loop/ISSUE_KEY/passes`). For `/brainstorm` runs,
   also check `vision/PROJECT_SLUG/*`.
2. **specs/issue-{KEY}-progress.md** — especially `## Errors`, loop-pass
   sections, and Evidence lines.
3. **GitHub issues/PRs** for the key, if the repo works through them
   (`gh issue view`, `gh pr view`).
4. **git log** for the branch or timeframe (`git log --oneline --since=...`).
5. The current conversation, when the session is this one.

## Step 2 — Look for improvement candidates

Scan the record for candidates in these categories:

- **Navigation**: how easy was it for the agent to find the right files? Were
  there hidden dependencies between files? Would a **navigation pointer** (a
  one-line pointer in AGENTS.md or a skill to the doc/module that matters)
  make it easier? _Use when_ the session spent a long time locating
  information.
- **Automated checks**: are there checks that could catch errors the agent
  made — linting, typing, tests, filesystem linters? Read the repo's own check
  command first (`package.json`/Makefile `lint`/`check`/`test` targets, the CI
  workflow), so a check that already exists but sits unwired or silently
  broken is the finding, not a reinvention. A repo with **no guardrail** (no
  pre-commit hook and no CI job running its lint/typecheck/test command) is
  itself a finding — an un-linted repo is a standing missed opportunity, not a
  neutral default. _Use when_ the agent made a mistake an automated check
  could have caught, or the repo has no guardrail at all.
- **Review rules**: should `@code-reviewer`, `@standards-reviewer`, or
  `@spec-fidelity-reviewer` be given a new rule to enforce? Should an existing
  rule be removed or clarified? Classify the violation first: a **mechanical**
  one (fixed syntactic pattern, banned API, import shape, file-location rule)
  gets a deterministic check, full stop — a linter rule, pre-commit hook, or
  CI job, whichever the repo's language and existing guardrail make cheapest.
  Default to building the check over writing the rule. Reserve prose rules for
  genuine **judgement calls** (cross-file consistency, "matches the
  surrounding style", anything no guardrail could substitute for). _Use when_
  the review agents failed to catch a mistake.
- **Steering files**: are there instructions in AGENTS.md (repo or global),
  skills, or agent prompts that should move into standards or automated
  checks instead? Look for **no-ops** — instructions that provably did not
  modify the agent's behavior this session. _Use when_ the steering files are
  large, or an instruction was ignored or redundant.
- **Tool economy**: did the agent make expensive tool calls that could be
  streamlined? Is any custom tooling (CLIs, MCP servers) particularly
  token-inefficient? _Use when_ the agent made an expensive tool call.
- **Information access**: opportunities to increase the agent's access to
  information — teeing dev server logs, read-only access to third-party
  services, capturing an external doc the agent had to guess at. _Use when_ a
  crucial piece of information was not available to the agent.
- **Workflow friction**: gates, budgets, or flags in the spec-driven pipeline
  that misfired this session (a DoD item that was unverifiable, a seam the
  Test Strategy got wrong, a loop budget that exhausted too early). _Use when_
  the pipeline itself — not the code — was the bottleneck.

## Step 3 — Present candidates

Present the candidates to the user, **in order of severity** (most severe
first). For each candidate:

```
### <N>. <Category> — <one-line finding>
Evidence:   <what happened in the session, quoted or cited>
Proposal:   <the concrete change: file to edit, check to build, rule to add>
Cost:       <low | medium | high>
```

Do not apply anything. The retro proposes; the user disposes. If the user
approves a candidate that records an architectural ruling, append it to
`decisions.md` as a dated block (per the spec-driven-workflow skill) and
mirror it via `mem_save` with `scope: global`.

## Reference

### Implementation vs review context pressure

All work goes through two stages: implementation and review. The
implementation agent (`@spec-implementer`) has the most **context pressure** —
exploration, writing code, debugging. The review agents have the least: they
receive a diff, no exploration, usually no code-writing. This means review
agents should carry coding standards, not the implementer. When proposing a
new rule, prefer adding it to a reviewer over bloating the implementer prompt.

### Files in this environment

- **AGENTS.md** (repo + `~/.config/opencode/AGENTS.md`): pushed into every
  agent's context. Use incredibly sparingly — mostly **navigation pointers**.
- **decisions.md**: dated rulings, consulted before drafting specs. This repo
  has no CODING_STANDARDS.md; judgement-call standards live in AGENTS.md rules
  and reviewer prompts, and rulings live in decisions.md.
- **skills/**: loaded on demand; their descriptions ride in every context —
  keep descriptions sharp and bodies lean.
- **agents/**: subagent prompts; review agents are the right home for
  standards enforcement.
- **specs/**: per-issue findings/spec/progress — reference material, pointed
  to by commands, never loaded wholesale.
