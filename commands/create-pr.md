---
description: Create a PR with a comprehensive description and context
argument-hint: <pr-title>
agent: build
model: opencode/qwen3.5-plus
---

# Create PR: $ARGUMENTS

## Step 1 — Check branch state

```bash
git status --short
git branch --show-current
```

If there are uncommitted changes, stop and ask the user how to handle them
(commit, stash, or abort). Do **not** auto-commit silently — the user might
have intentional WIP they don't want in the PR.

If the user confirms a commit, use:
```bash
git add -A
git commit -m "<message you propose to the user first>"
```

## Step 2 — Analyse changes

```bash
git diff $(git merge-base HEAD main)..HEAD
git log $(git merge-base HEAD main)..HEAD --oneline
```

## Step 3 — Draft the PR description

Generate a description following this template:

```markdown
## What Changed
- <bullet points of key changes, grounded in the diff>

## Why This Change
- <business or technical justification, inferred from commits and diff>

## Testing Done
- <what tests were added or run; "manual smoke test" is acceptable if true>

## Related Issues
- <issue keys mentioned in commit messages, e.g. FEAT-123>
```

## Step 4 — Write the description to disk

Write the description to `pr-description.md` in the repo root.

**Important:** if `pr-description.md` is not already in `.gitignore`, append it
before writing the file. This file is a working artefact — it must never be
committed.

```bash
grep -qxF 'pr-description.md' .gitignore 2>/dev/null || echo 'pr-description.md' >> .gitignore
```

## Step 5 — Create the PR

```bash
gh pr create --title "$ARGUMENTS" --body-file pr-description.md
```

If `gh` is not authenticated, stop and tell the user to run `gh auth login`.

## Step 6 — Clean up

```bash
rm pr-description.md
```

Print the PR URL returned by `gh pr create`.
