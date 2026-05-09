---
description: Generate a comprehensive handover document for async collaboration
agent: build
model: opencode/qwen3.6-plus
---

# Create Handover

Generate a handover document that another engineer (or another agent) can pick
up cold. Be specific. Vague handovers waste the next person's first hour.

## Collect technical context

Run these commands and incorporate the output into the document:

```bash
git branch --show-current
git log -10 --oneline
git status --short
git diff --stat $(git merge-base HEAD main)..HEAD 2>/dev/null
```

## Document structure

Use this exact structure:

```markdown
# Handover — <YYYY-MM-DD HH:MM>

## 1. Progress Summary
- Tasks completed this session
- Current implementation state
- What's working, what's blocked

## 2. Technical Context
- Branch: <current branch>
- Recent commits:
  <git log -10 --oneline output>
- Modified files:
  <git status --short output>
- Diff stats vs main:
  <git diff --stat output>

## 3. Decisions Made
- Technical choices and the reasoning behind them
- Trade-offs considered
- Alternatives rejected (and why)

## 4. Active Blockers
- External dependencies waiting on
- Unresolved technical questions
- Resource needs

## 5. Next Steps

### Immediate Priority
1. <specific task with acceptance criteria>

### Secondary Tasks
2. <follow-up work>

### Future Considerations
3. <tech debt, optimisations>

## 6. References
- Relevant documentation links
- Related PRs/issues
- Design docs or specs
```

## Save

Create the `handovers/` directory if it doesn't exist, then write the document to:

```
handovers/handover-$(date +%Y%m%d-%H%M%S).md
```

Print the resulting path so the user can open it.
