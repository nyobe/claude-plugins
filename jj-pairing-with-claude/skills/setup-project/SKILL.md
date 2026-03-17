---
name: setup-project
description: Add a project-level SessionStart hook that scaffolds a git worktree in jj workspaces
user_invocable: true
disable-model-invocation: true
---

# Set up project worktree hooks

Projects that need git compatibility in jj workspaces (e.g., for submodules or
git-dependent tooling) can add a project-level SessionStart hook that scaffolds
a git worktree entry. The user can customize the script to also warm
dependencies.

## Steps

1. Check whether a SessionStart hook already exists in:
   - `.claude/settings.json` (project, committed)
   - `.claude/settings.local.json` (project, local/gitignored)

   If SessionStart hooks exist, show them to the user and ask whether to add
   alongside them or skip.

2. Ask the user where to install:
   - **Project local** (`.claude/settings.local.json`, gitignored) — recommended
   - **Project** (`.claude/settings.json`, committed, shared with team)

3. Create `.claude/hooks/worktree-init.sh`:

```bash
#!/usr/bin/env bash

# Project-level SessionStart hook for jj worktrees.
# Scaffolds a git worktree so git-dependent tools (submodules, Makefile) work,
# then warms up any project-specific dependencies.
#
# Customize the "warm dependencies" section below for your project.

case "$PWD" in
  */.claude/worktrees/*)
    # Scaffold git worktree for tool compatibility (idempotent)
    ${CLAUDE_SKILL_DIR}/../../scripts/git-scaffold-worktree.sh "$PWD"

    # Warm dependencies — customize for your project:
    # go mod download
    # yarn install --frozen-lockfile
    ;;
esac
```

   The `${CLAUDE_SKILL_DIR}` path above will already be expanded to an absolute
   path when you read these instructions, so use that concrete path directly.

4. Make the script executable: `chmod +x .claude/hooks/worktree-init.sh`

5. Add the following to the `hooks` object in the chosen settings file:

```json
"SessionStart": [
  {
    "matcher": "startup",
    "hooks": [
      {
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/worktree-init.sh"
      }
    ]
  }
]
```

6. Show the user what was created and suggest they customize the warm
   dependencies section for their project.

