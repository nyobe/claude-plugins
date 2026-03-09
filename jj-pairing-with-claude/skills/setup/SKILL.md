---
name: setup
description: Install jj-pairing-with-claude worktree hooks into your Claude Code settings
user_invocable: true
---

# Install jj worktree hooks

WorktreeCreate and WorktreeRemove hooks can't be loaded from a plugin, so this
skill installs them into the user's Claude Code settings.

These hooks handle jj workspace creation/removal. For git worktree scaffolding
(needed by repos with submodules or git-dependent tooling), use the
`setup-project` skill separately.

## Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/plugin-root.sh` to get the absolute path
   to the plugin root. Store this as `PLUGIN_ROOT`.

2. Check whether WorktreeCreate or WorktreeRemove hooks already exist in either:
   - `~/.claude/settings.json` (global)
   - `.claude/settings.json` (project, committed)
   - `.claude/settings.local.json` (project, local/gitignored)

   If they exist in any location, tell the user where and ask whether to
   overwrite them.

3. If hooks are not already installed, ask the user where to install them:
   - **Global** (`~/.claude/settings.json`) — applies to all projects (recommended)
   - **Project** (`.claude/settings.json`) — committed, shared with team
   - **Project local** (`.claude/settings.local.json`) — gitignored, personal

4. Add the following to the `hooks` object in the chosen settings file
   (create the `hooks` key if it doesn't exist):

```json
"WorktreeCreate": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "<PLUGIN_ROOT>/scripts/jj-worktree-create.sh"
      }
    ]
  }
],
"WorktreeRemove": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "<PLUGIN_ROOT>/scripts/jj-worktree-remove.sh"
      }
    ]
  }
]
```

   Replace `<PLUGIN_ROOT>` with the actual absolute path from step 1.

5. Show the user what was added and where, and confirm the installation succeeded.
6. Tell the user to restart Claude Code for the hooks to take effect.
7. Suggest running `/setup-project` if their repo needs git worktree scaffolding.
