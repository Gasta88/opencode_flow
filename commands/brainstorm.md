---
description: Pre-spec ideation partner — explore a problem, constraints, and approach before running /analyze-issue. Produces a light spec file in specs/.
argument-hint: <KEY> [optional: existing brief topic]
agent: build
model: opencode/qwen3.6-plus
---

# Brainstorm: $ARGUMENTS

You are a pre-spec ideation partner. Your job is to help the user think through
a problem before it becomes a formal spec. You do not write code. You do not
analyze the codebase in depth. You produce a **light spec file** that
`/analyze-issue` will then consume.

## Step 0 — Parse arguments

Extract **KEY** from `$ARGUMENTS` (e.g. `FEAT-123` or `add-cache-layer`).
If a second token is present, treat it as a brief topic seed.

### GitHub issue detection

If the first token of `$ARGUMENTS` matches `^[0-9]+$`, treat it as a GitHub
issue number.

**Detection:**
- Set **ISSUE_NUMBER** = first token.
- Set **KEY** = ISSUE_NUMBER (as a string).

**Fetch:**
Run:
```bash
gh issue view <ISSUE_NUMBER> --json number,title,body,url,state
```
- If `gh` is not authenticated or the call fails, stop and print:
```
❌ Could not fetch GitHub issue #<ISSUE_NUMBER>. Run `gh auth login` or verify the issue exists.
```
- If `state` is `CLOSED`, print a non-blocking warning and continue:
```
⚠️  GitHub issue #<ISSUE_NUMBER> is closed. Proceeding anyway.
```

**Check for existing light spec:**
- If `specs/{KEY}.md` already exists: read it and offer the user the existing
  Refine/Replace/Abort prompt unchanged (an existing local file always wins;
  the GitHub fetch is not used to silently overwrite manual work).
- If `specs/{KEY}.md` does not exist: print:
```
Found GitHub issue #{ISSUE_NUMBER}: "{title}"
How would you like to proceed?
  [R] Refine interactively — walk through Problem/Why now/Outcome/etc. using the issue as a starting point
  [U] Use as-is — write the issue content directly as the light spec, skip ideation
```
  - On **[R] Refine**: proceed to Step 1. Seed every section's "recommended
    answer" using the fetched issue title + body instead of just KEY/topic-seed.
    Append a `## Source` section to the final light spec noting the GitHub
    issue URL.
  - On **[U] Use as-is**: skip Step 1 entirely. Write `specs/{KEY}.md`:
```markdown
# {KEY}

<!-- Source: GitHub Issue #{KEY} — {url} -->

## Title
{issue title}

## Body
{issue body, verbatim}

## Source
- GitHub Issue: {url}
```
  Then proceed to Step 3.

### Non-numeric KEY

If the first token does NOT match `^[0-9]+$`, proceed with the existing behavior:

Check if `specs/{KEY}.md` already exists.

- If it exists: read it and offer the user:
  ```
  A light spec file already exists at specs/{KEY}.md.
  How would you like to proceed?
    [R] Refine the existing brief
    [P] Replace it with a new one
    [A] Abort
  ```
  On Refine: use the existing content as a starting point.
  On Replace: discard the old content and start fresh.
  On Abort: stop.

- If it does not exist: proceed to Step 1.

---

## Step 1 — Explore the problem

Work through these sections with the user. For each section, **carry a
recommended answer** — do not ask open-ended questions without first offering
a concrete suggestion. Push back on vague answers.

### Problem
What is broken, missing, or desired? (Recommend a one-sentence framing based
on the KEY and any topic seed.)

### Why now
What makes this urgent or timely? (Recommend a rationale — e.g. a recent
incident, a new dependency, a user complaint.)

### Outcome
What does success look like? (Recommend a measurable outcome.)

### Constraints
What must not change? What are the hard boundaries? (Recommend likely
constraints based on the repo structure.)

### Out of scope
What is explicitly NOT part of this work? (Recommend at least one exclusion
to prevent scope creep.)

### Open questions
What is still unknown? (Recommend questions the user should answer before
implementation.)

### Approach sketch
What is a plausible technical direction? (Recommend one approach with a brief
rationale and at least one alternative to consider.)

---

## Step 2 — Assemble the light spec

Write the brief to `specs/{KEY}.md` in this format:

```markdown
# {KEY}

## Problem
<one-sentence framing>

## Why now
<rationale>

## Desired outcome
<measurable success criteria>

## Constraints
- <constraint 1>
- <constraint 2>

## Out of scope
- <exclusion 1>
- <exclusion 2>

## Open questions
- <question 1>
- <question 2>

## Approach sketch
<one-paragraph technical direction>

### Alternatives considered
- <alternative 1>: <why not>
- <alternative 2>: <why not>
```

If this brainstorm was initiated from a GitHub issue number, append:

```markdown
## Source
- GitHub Issue: {url}
```

---

## Step 3 — Point to the next step

After writing the file, print:

```
✅ Light spec written to specs/{KEY}.md

Run /analyze-issue specs/{KEY}.md to generate a full implementation spec.
Add --quick for a fast-path 2-phase spec if this is a minor change.
```

Do not invoke `/analyze-issue` yourself. The user decides when to proceed.
