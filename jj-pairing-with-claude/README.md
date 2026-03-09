# jj-pairing-with-claude

A Claude Code plugin that uses [jj](https://martinvonz.github.io/jj/) workspaces to give agents an isolated working copy while keeping changes visible and editable from your main workspace. You and the agent work on the same repo simultaneously — no branches, no merging, no waiting.

## How it works

```
Your workspace                          Agent workspace
(.claude/worktrees/fix-auth/)
┌─────────────┐                        ┌─────────────┐
│  jj @       │  jj workspace          │  jj @       │
│  (default)  │  update-stale          │  (fix-auth) │
│             │ ◄───────────────────── │             │
│             │ ─────────────────────► │             │
│  edit the   │  auto-snapshot         │  Edit/Write │
│  agent's    │  after each            │  tool calls │
│  change     │  tool use              │             │
└─────────────┘                        └─────────────┘
         │                                    │
         └──────────── shared repo ───────────┘
```

When Claude enters a worktree, the plugin creates a **jj workspace** rooted at `trunk()`. The agent edits files normally, and a PostToolUse hook snapshots each change so it appears in `jj log` immediately. You can inspect, edit, or rebase the agent's work from your own workspace at any time.

Before the agent processes each prompt, a UserPromptSubmit hook detects if you've touched its working commit and runs `jj workspace update-stale` to pull in your changes. The agent gets a context message telling it to re-read affected files.

## The collaboration loop

1. **You** ask Claude to work on something. It enters a worktree automatically.
2. **Claude** edits files. Each edit is auto-snapshotted into a jj change.
3. **You** see the change in `jj log`. You can:
   - Read the diff: `jj diff -r <change>`
   - Edit the agent's files: `jj edit <change>`, make changes, `jj edit <your-change>`
   - Leave inline instructions: add `# CLAUDE: use bcrypt here` comments
   - Rebase it: `jj rebase -r <change> -d <target>`
4. **Claude** picks up your edits on its next prompt (auto-sync). It sees which files changed and any `CLAUDE:` comments you left.
5. **Claude** finishes: `jj describe -m "..."` then `jj new` to seal the commit.

### Inline comments with `CLAUDE:`

You can leave instructions for the agent directly in the code using any comment style:

```python
# CLAUDE: this should validate the email format
def create_user(email, name):
    ...
```

```javascript
// CLAUDE: add rate limiting to this endpoint
app.post('/api/submit', handler)
```

When the sync hook detects these in the diff, it surfaces them to the agent with file and line number. The agent addresses them and removes the comments when done.

## Prerequisites

- [jj](https://martinvonz.github.io/jj/) (Jujutsu VCS)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with plugin support
- A jj-managed repository (colocated with git is fine)

## Installation

### 1. Install the plugin

```sh
claude plugins add /path/to/claude-plugins/jj-pairing-with-claude
```

This loads the auto-snapshot, workspace sync, and session context hooks automatically.

### 2. Set up worktree hooks

The WorktreeCreate and WorktreeRemove hooks can't be loaded from a plugin — they need to be in your Claude Code settings. Run the setup skill:

```
/setup
```

This installs hooks into your global or project settings. Restart Claude Code afterward.

### 3. (Optional) Set up git worktree scaffolding

If your project has git submodules or git-dependent tooling, run:

```
/setup-project
```

This creates a project-level SessionStart hook that scaffolds a git worktree entry so tools like `git submodule`, `make`, etc. work inside the jj workspace. You can also customize the generated script to warm dependencies (e.g., `go mod download`, `yarn install`).

## What each hook does

| Hook | Trigger | Script | Purpose |
|------|---------|--------|---------|
| **WorktreeCreate** | `EnterWorktree` | `jj-worktree-create.sh` | Creates jj workspace at `.claude/worktrees/<name>` |
| **WorktreeRemove** | Worktree exit | `jj-worktree-remove.sh` | Forgets workspace, cleans up directory |
| **PostToolUse** | After Edit/Write | `jj-snapshot.sh` | Snapshots changes so they're visible in `jj log` |
| **UserPromptSubmit** | Before each prompt | `jj-workspace-sync.sh` | Detects stale workspace, syncs user changes |
| **SessionStart** | Session starts in worktree | `jj-worktree-context.sh` | Teaches the agent how to use jj |

## Design choices

**Why jj workspaces instead of git worktrees?** jj workspaces share a single repo but have independent working copies. Changes are visible across workspaces immediately via snapshots — no push/pull cycle. The user can edit the agent's working commit directly, something that's awkward with git worktrees.

**Why snapshot on every Edit/Write?** This keeps the agent's work continuously visible without requiring explicit commits. The agent can `jj describe` when the work is coherent, rather than committing prematurely.

**Why auto-sync on UserPromptSubmit?** This is the natural point where the user has done something (typed a message) and the agent is about to act. Syncing here means the agent always works with the latest state.

## Multi-agent workflows

Each agent gets its own jj workspace — that's the intended grain. Multiple agents work in parallel without interfering with each other, and you orchestrate their changes through jj's change graph.

```
User workspace (default)
├── Agent A workspace (fix-auth)      ← own working copy
├── Agent B workspace (add-tests)     ← own working copy
└── Agent C workspace (refactor-db)   ← own working copy

All share the same repo. All visible in jj log.
```

**How it plays out:**

1. Launch multiple agents — each enters its own worktree, which becomes a jj workspace.
2. Each agent edits freely. Auto-snapshots make their changes visible in `jj log` immediately.
3. You see all agents' in-flight work in one `jj log`. You can:
   - Stack changes: `jj rebase -r agent-b -d agent-a`
   - Squash related work: `jj squash --from agent-b --into agent-a`
   - Resolve conflicts between agents before they're even done
4. Each agent keeps working in its own workspace, unaware of the others.

The key insight is that jj separates "working copy" from "change graph." Every agent gets its own working copy, but they all contribute to the same change graph that you manage. This turns multi-agent coordination from a file-locking problem into a DAG-editing problem — and jj is very good at DAG editing.

In Claude Code, this happens when you use the `Agent` tool with `isolation: "worktree"` (each subagent gets its own worktree), or when you run multiple `claude` sessions that each enter their own worktree.

## Limitations

- **No automatic conflict resolution.** If you and the agent edit the same lines, jj will mark conflicts. You'll need to resolve them manually.
- **Single agent per workspace.** Each jj workspace should have one agent. Multiple agents on the same workspace will conflict.
- **Snapshot performance.** The snapshot hook uses `snapshot.auto-track=all()`, which scans all files. This may be slow in very large repos.
