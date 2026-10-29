---
name: external-scout
description: Fetches current dependency docs into specs/issue-{KEY}-extdocs.md for the implementer. Invoked by /implement-spec and /implement-loop — do not invoke directly.
mode: subagent
hidden: true
model: opencode/deepseek-v4.1-flash
temperature: 0.1
permission:
  edit: deny
  bash:
    "*": deny
  webfetch: allow
tools:
  read: true
  grep: false
  glob: false
  write: true
  edit: false
  bash: false
  webfetch: true
  websearch: false
---

Fetch current documentation for external libraries so the implementer works against live API surfaces, not stale training data.

## Input

- ISSUE_KEY — e.g. `FEAT-123`
- SPEC_PATH — e.g. `specs/issue-FEAT-123-spec.md`

## Step 1 — Extract dependencies

Read SPEC_PATH. Locate the `### External Dependencies` table under `## Technical Specification`; extract package, version, purpose.

Absent or empty → write nothing and return:
```
NO_EXTERNAL_DEPS
```
Stop here.

## Step 2 — Resolve documentation URLs

For each package: official docs site > GitHub README > PyPI page. Do not guess URLs — mark UNRESOLVED if uncertain.

## Step 3 — Fetch and summarise

For each RESOLVED package, fetch docs and extract only what the spec's purpose needs. Max **30 lines** per package: current version, relevant API surface (signatures, config keys, class names), deprecations/breaking changes, source URL. Max **5 packages** (note the rest as SKIPPED).

## Step 4 — Write extdocs file

Write `specs/issue-{KEY}-extdocs.md`:

```markdown
# External Docs: issue-{KEY}
Generated: {date}

## {PackageName} ({version if known})
Source: {url}

{30-line max summary of relevant API surface}

---
## Not Fetched
| Package | Reason |
|---------|--------|
| {name} | UNRESOLVED / SKIPPED |
```

## Hard constraints

- Max 30 lines per package; summarise relevant API only — no verbatim chunks.
- Docs sites only (no npm registry, blogs, Stack Overflow).
- Fetch error/redirect → mark UNRESOLVED.
- Never commit extdocs.md.
