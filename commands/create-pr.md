---
description: Create a PR with a comprehensive description and context
argument-hint: <pr-title>
agent: build
model: opencode/qwen3.5-plus
---

# Create PR: $ARGUMENTS

## Step 1 — Analyse changes

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git status --short
git branch --show-current
git diff $(git merge-base HEAD $BASE_BRANCH)..HEAD
git log $(git merge-base HEAD $BASE_BRANCH)..HEAD --oneline
```

## Step 2 — Review and commit changes

If the working tree is clean (no output from `git status --short`), skip to Step 3.

1. Run `git status --short` and print the full list of changed files to the user.

2. Scan the file list for common risk patterns before proposing anything:
   `.env`, `.env.*`, `*.pem`, `*.key`, `*credentials*`, `*secret*`, `.DS_Store`
   (belt-and-suspenders even though `.gitignore` should already catch these — a
   file already tracked before being gitignored won't be caught by `.gitignore`
   alone).

   If any risk-pattern file appears in the changed-files list, stop and print:
   ```
   ⚠️  <file> matches a sensitive-file pattern and is about to be committed.
      Remove it from the working tree or add it to .gitignore before
      re-running /create-pr.
   ```

3. If no risk patterns are found, generate the commit message from the diff as
   before. Print the proposed commit message and the file list together, and ask
   the user to confirm before running `git add -A && git commit`.

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

**Important:** never commit `pr-description.md`, it is a working artefact — it must never be
committed.


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
