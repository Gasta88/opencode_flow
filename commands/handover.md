---
description: Generate a comprehensive handover document for async collaboration
argument-hint: <optional — describe what the next session will focus on>
agent: build
model: opencode/qwen3.6-plus
---

# Create Handover

Generate a handover another engineer (or agent) can pick up cold. Be specific — vague handovers waste the next person's first hour.

## Collect technical context

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)
[ -z "$BASE_BRANCH" ] && BASE_BRANCH=main
git branch --show-current
git log -10 --oneline
git status --short
git diff --stat $(git merge-base HEAD $BASE_BRANCH)..HEAD 2>/dev/null
```

## Save handover via Engram

Call `mem_session_summary` with:
```markdown
## Goal
<What was being worked on this session>

## Instructions
<User preferences or constraints discovered — skip if none>

## Discoveries
- <Technical findings, gotchas, non-obvious learnings>
- <Include relevant git context: branch, recent commits, modified files>

## Accomplished
- [Completed items with key details]

## Next Steps
- [What remains to be done — for the next session]

## Relevant Files
- path/to/file — [what it does or what changed]
```

## Fallback: Markdown handover file

If Engram is unavailable, write this structure:
```markdown
# Handover — <YYYY-MM-DD HH:MM>

## 1. Progress Summary
- Tasks completed, current state, what's working/blocked

## 2. Technical Context
- Branch / commits / modified files / diff stats (from the commands above)

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

Create `handovers/` if needed, write to `handovers/handover-$(date +%Y%m%d-%H%M%S).md`, and print the path.
