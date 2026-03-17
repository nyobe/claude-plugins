---
name: setup
description: Install jj-pairing-with-claude worktree hooks into your Claude Code settings
user_invocable: true
disable-model-invocation: true
---

# Install jj worktree hooks

WorktreeCreate and WorktreeRemove hooks can't be loaded from a plugin, so this
skill installs them into the user's Claude Code settings.

These hooks handle jj workspace creation/removal. For git worktree scaffolding
(needed by repos with submodules or git-dependent tooling), use the
`setup-project` skill separately.

## Steps

1. Check whether WorktreeCreate or WorktreeRemove hooks already exist in either:
   - `~/.claude/settings.json` (global)
   - `.claude/settings.json` (project, committed)
   - `.claude/settings.local.json` (project, local/gitignored)

   If they exist in any location, tell the user where and ask whether to
   overwrite them.

2. If hooks are not already installed, ask the user where to install them:
   - **Global** (`~/.claude/settings.json`) — applies to all projects (recommended)
   - **Project** (`.claude/settings.json`) — committed, shared with team
   - **Project local** (`.claude/settings.local.json`) — gitignored, personal

3. Add the following to the `hooks` object in the chosen settings file
   (create the `hooks` key if it doesn't exist):

```json
"WorktreeCreate": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_SKILL_DIR}/../../scripts/jj-worktree-create.sh"
      }
    ]
  }
],
"WorktreeRemove": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_SKILL_DIR}/../../scripts/jj-worktree-remove.sh"
      }
    ]
  }
]
```

   The `${CLAUDE_SKILL_DIR}` paths above will already be expanded to absolute
   paths when you read these instructions. Normalize them (resolve the `../..`)
   before writing to the settings file.

4. Show the user what was added and where, and confirm the installation succeeded.
5. Tell the user to restart Claude Code for the hooks to take effect.
6. Suggest running `/setup-project` if their repo needs git worktree scaffolding.
