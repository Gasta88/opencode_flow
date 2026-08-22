---
description: Generate a comprehensive handover document for async collaboration
argument-hint: <optional — describe what the next session will focus on>
agent: build
model: opencode/qwen3.6-plus
---

# Create Handover

Generate a handover document that another engineer (or another agent) can pick
up cold. Be specific. Vague handovers waste the next person's first hour.

## Collect technical context

Run these commands and incorporate the output into the document:

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git branch --show-current
git log -10 --oneline
git status --short
git diff --stat $(git merge-base HEAD $BASE_BRANCH)..HEAD 2>/dev/null
```

## Document structure

Use this structure:
```markdown
# Handover — <YYYY-MM-DD HH:MM>

## 1. Progress Summary
- Tasks completed, current state, what's working/blocked

## 2. Technical Context
- Branch: <branch>
- Commits: <git log -10 --oneline>
- Modified: <git status --short>
- Diff stats: <git diff --stat vs main>

## 3. Decisions Made
- Technical choices, trade-offs, rejected alternatives

## 4. Active Blockers
- External dependencies, unresolved questions, resource needs

## 5. Next Steps
1. <immediate task with acceptance criteria>
2. <follow-up work>
3. <tech debt, optimisations>

## 6. References
- Links to docs, PRs, specs

## 7. Next Session
Focus: $ARGUMENTS (or "general continuation")
Skills: spec-driven-workflow
```

## Save

Create the `handovers/` directory if it doesn't exist, then write the document to:

```
handovers/handover-$(date +%Y%m%d-%H%M%S).md
```

Print the resulting path so the user can open it.
