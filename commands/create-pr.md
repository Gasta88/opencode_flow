---
description: Create a PR with a comprehensive description and context
argument-hint: <pr-title>
agent: build
model: opencode/qwen3.5-plus
---

# Create PR: $ARGUMENTS

## Step 1 — Commit any uncommitted changes

Run `git status --short` to check for uncommitted changes.

If the working tree is clean (no output), skip to Step 2.

1. Print the full list of changed files to the user.

2. Scan for risk patterns: `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`. If found, stop with:
   `⚠️  <file> matches a sensitive-file pattern. Remove it or add to .gitignore before re-running /create-pr.`

3. If no risk patterns are found, generate the commit message from the diff.
   Print the proposed commit message and the file list together, and ask
   the user to confirm before running `git add -A && git commit`.

## Step 2 — Analyse changes

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git status --short
git branch --show-current
git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

## Step 3 — Gather evidence

Before drafting, collect concrete evidence that the change works:

1. If a test suite exists, run it and capture the output. If a test was added or
   fixed by this change, note its name and its before/after result.
2. If the change is visual and screenshots are feasible, note that; otherwise
   rely on execution-based evidence (test results, console output).
3. If no automated evidence exists, use what is true — e.g. "manual smoke test:
   <what was exercised>". Never invent evidence.

## Step 4 — Draft the PR description

Skip all preambles and keep prose brief. Use the project's domain language
(from `GLOSSARY.md` if it exists). Generate a description following this
template:

```markdown
## Summary

<the smallest visual that makes the key point clear — see guidance below>

## Evidence

- **Before:** <screenshot/output/failing test run>
  **After:** <screenshot/output/passing test run>

## Merge Danger

**Door:** <one-way | two-way>

<optional: one-sentence description>

**Blast Radius:** <one-word description>

<optional: potential ramifications of merge>

## Related Issues
- <issue keys mentioned in commit messages, e.g. FEAT-123>
```

### Summary guidance

Pick the smallest view that makes the key point clear. Place each visual next
to the short text it supports. You may use one of these or several; it is
unlikely you will use all of them — do not overwhelm the reader.

- **Logic or algorithm** → pseudocode:
  ```text
  on(save)
    if content is unchanged
      return cached result
    write new content
  ```
- **Runtime control flow** → call tree:
  ```text
  submitForm
    createSession
      persistPrompt
    navigateToSession
  ```
- **UI structure** → component tree, including state and module boundaries that matter.
- **File responsibility or broad refactor** → shallow file tree with one-line annotations.
- **Component interaction / data flow** → Mermaid (`sequenceDiagram`, `flowchart`).
- **The point is what changes and the surrounding shape already exists** → `diff`-shaped sketch (component trees, file layouts, call trees, or control flow with `+`/`-` markers).
- **Most of a block is new** → show the whole block as code.

### Evidence guidance

Screenshots are S-tier when the change is visual and the environment supports
them. Execution-based evidence is A-tier: test results, console output — show
the exact test that failed before and passes now.

### Merge Danger guidance

- **Door**: a two-way door can be walked back (cheap revert); a one-way door
  cannot (destructive actions, schema drops, data migrations, removed public
  API, hard-to-reverse decisions).
- **Blast Radius**: the potential impact or scope of the change — one word
  (e.g. `none`, `single-module`, `all-consumers`, `schema`), then optional
  ramifications (breakages for consumers, layout shift, migrations required).

## Step 5 — Write the description to disk

Write the description to `pr-description.md` in the repo root.

**Important:** never commit `pr-description.md`, it is a working artefact — it must never be
committed.


## Step 6 — Create the PR

```bash
gh pr create --title "$ARGUMENTS" --body-file pr-description.md
```

If `gh` is not authenticated, stop and tell the user to run `gh auth login`.

## Step 7 — Clean up


```bash
rm pr-description.md
```

Print the PR URL returned by `gh pr create`.
