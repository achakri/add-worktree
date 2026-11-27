# add-worktree

A Claude Code skill that creates a Git worktree and copies your Claude Code
configuration and `.env` file into it, so a new session there starts with the
same setup. A second skill, `remove-worktree`, cleans up when you are done.

```
/add-worktree feature/login
```

For a project in a folder named `my-app`, this creates `../my-app_feature-login`
on the branch `feature/login`, then opens a new terminal tab running Claude
there.

## Requirements

- Git and Bash. Tested on macOS with Bash 3.2 and Git 2.55. Linux and Windows
  have not been tested.
- A repository with at least one commit.
- [Claude Code](https://code.claude.com/docs), to use it as a skill.

## Install

### As a plugin (recommended)

Run these inside Claude Code:

```
/plugin marketplace add achakri/add-worktree
/plugin install add-worktree@achakri-tools
```

Then run `/reload-plugins`, or start a new session.

The command is `/add-worktree <name>`. The full form,
`/add-worktree:add-worktree <name>`, also works, and is the one to use if
another command is already called `/add-worktree`.

**If the repository is private**, you need read access to it and Git
credentials that work without a prompt. With the GitHub CLI:

```bash
gh auth login
gh auth setup-git
```

If you have no GitHub SSH key, start Claude Code with
`CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1`.

To update:

```
/plugin marketplace update achakri-tools
```

then, in your shell:

```bash
claude plugin update add-worktree@achakri-tools
```

To uninstall, in your shell:

```bash
claude plugin uninstall add-worktree@achakri-tools
claude plugin marketplace remove achakri-tools
```

### As a personal skill

To install without the plugin system:

```bash
git clone https://github.com/achakri/add-worktree.git
mkdir -p ~/.claude/skills
cp -R add-worktree/skills/add-worktree add-worktree/skills/remove-worktree ~/.claude/skills/
```

If either folder already exists in `~/.claude/skills`, move it aside first, or
`cp` will nest the new copy inside it.

Use one install method, not both.

## Usage

```
/add-worktree <name>
```

`<name>` is the branch name. It may contain letters, digits, `.`, `_`, `-` and
`/`, and must be a valid Git branch name. `HEAD` and names starting with
`refs/` are rejected. If you leave it out, Claude asks for it.

You can also run the script without Claude, from any checkout of your project:

```bash
bash /path/to/add-worktree/skills/add-worktree/scripts/add-worktree.sh <name>
```

## What it does

### Folder

The worktree is created next to the main checkout as `<project>_<name>`, where
`<project>` is the main checkout's folder name, even if you run it from another
worktree. Any `/` in the name becomes `-` in the folder name.

### Branch

If `origin` exists, it is fetched first, and a failed fetch stops the script.

| Situation | Result |
| --- | --- |
| Local branch, behind `origin` | Used, and fast-forwarded |
| Local branch, diverged from `origin` | Used unchanged, with a warning |
| Local branch, otherwise | Used unchanged |
| Branch only on `origin` | Local tracking branch created |
| New branch | Created from the remote default branch, or from `HEAD` if that is unavailable |

### Copied files

These are copied from the main checkout, when they exist:

- `.claude/` (except `.claude/worktrees/`)
- `CLAUDE.md`
- `CLAUDE.local.md`
- `.mcp.json`
- `.worktreeinclude`
- `.env` (only this name, at the root; not `.env.local` and the like)

`.worktreeinclude` is only copied. The script does not copy the files that its
patterns list.

### New tab

After a successful run, a new tab opens in your current terminal and starts
Claude in the worktree.

| Terminal | Notes |
| --- | --- |
| macOS Terminal | Presses Command-T, so macOS needs your permission (see below) |
| iTerm2 | macOS may ask to let your terminal control iTerm2. Not tested |
| tmux | Opens a new tmux window. Not tested with a real tmux |
| Others | No tab. A warning is shown with the command to run |

For macOS Terminal, allow **Terminal** in System Settings > Privacy & Security >
**Accessibility**, and accept the prompt to control **System Events** if it
appears. Do not switch applications while the tab is opening.

If the tab cannot be opened, the worktree is still created and the command to
start Claude is printed.

To skip the tab, set `ADD_WORKTREE_NO_TAB=1`:

```bash
ADD_WORKTREE_NO_TAB=1 bash /path/to/add-worktree.sh <name>
```

In Claude Code, ask for no tab when you run the skill.

### Rerunning

Running it again for an existing worktree only copies missing files, then opens
a new tab. It does not fetch or change the branch.

## Safety

When adding a worktree, the script:

- Never overwrites an existing file in the worktree.
- Never uses `--force` and never deletes anything.
- Stops if the target folder is used by something else, or if the branch is
  checked out in another folder.
- Does not copy files into a symlinked folder in the worktree.
- Never prints file contents.

### Secrets

`.env`, `.mcp.json`, `CLAUDE.local.md` and files under `.claude/` may contain
secrets.
The script warns about each copied file that Git does not ignore. Add the
private ones to your `.gitignore`, for example:

```gitignore
.env
CLAUDE.local.md
.claude/settings.local.json
.claude/worktrees/
# Only if it holds secrets:
.mcp.json
```

## Removing a worktree

In the Claude session of the worktree you are done with:

```
/remove-worktree
```

This removes that worktree, deletes its local branch, and ends the terminal
session, including Claude. Only you can run it; Claude cannot start it on its
own. With the plugin, the full form is `/add-worktree:remove-worktree`.

You can also run the script yourself, from inside the worktree:

```bash
bash /path/to/add-worktree/skills/remove-worktree/scripts/remove-worktree.sh
```

### What stops it

Nothing is removed if:

- There are uncommitted or untracked files.
- An ignored configuration file (`.env`, `CLAUDE.md`, `CLAUDE.local.md`,
  `.mcp.json`, `.worktreeinclude` or a file under `.claude/`) is new, or differs
  from the main checkout. This includes a file changed only in the main
  checkout.
- The branch has commits that are on no other local branch and on no branch of
  `origin`. A branch that was squash or rebase merged looks like this too.

To discard all of these and remove the worktree anyway:

```
/remove-worktree --force
```

Even with `--force`, it never removes the main checkout, deletes `main`,
`master` or the remote default branch, or removes a worktree that contains
another one. It also needs a branch to be checked out.

> **Warning:** other ignored files in the worktree, such as installed
> dependencies, build output or `.env.local`, are deleted without a check.

Branches on `origin` are never deleted.

### Terminal session

A few seconds after the removal, every process in the terminal is ended.

| Terminal | What closes |
| --- | --- |
| macOS Terminal | The session, then the tab with Command-W (same permission as for opening a tab). Not tested |
| iTerm2 | The session. Not tested |
| tmux | The current pane. Not tested |
| Others | The processes in the terminal |

If the tab stays open in macOS Terminal, close it yourself. If no terminal is
found, a warning is shown and nothing is ended.

To keep the session, set `REMOVE_WORKTREE_KEEP_SESSION=1`, or ask for it when
you run the skill.

## Troubleshooting

| Message | What to do |
| --- | --- |
| `there is no commit to start from` | Make a first commit, then retry |
| `already checked out in a different folder` | Work in that folder, or choose another branch |
| `target folder is used by something else` | Choose another name, or move that folder yourself |
| `that worktree is missing` | Check the path, then run `git worktree prune` |
| `single-branch clone?` | Check `remote.origin.fetch`, which may not cover that branch |

## Repository layout

```
.claude-plugin/
  plugin.json            Plugin manifest
  marketplace.json       Lets Claude Code install from this repository
skills/add-worktree/
  SKILL.md               Instructions Claude follows
  scripts/add-worktree.sh
skills/remove-worktree/
  SKILL.md
  scripts/remove-worktree.sh
LICENSE
```

## License

[MIT](LICENSE)
