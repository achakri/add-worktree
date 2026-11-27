# add-worktree

A Claude Code skill that creates a Git worktree and copies your Claude Code
configuration into it, so a new session there starts with the same setup.

```
/add-worktree feature/login
```

For a project in a folder named `my-app`, this creates `../my-app_feature-login`
on the branch `feature/login`, then prints the command to start Claude there.

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
cp -R add-worktree/skills/add-worktree ~/.claude/skills/
```

If `~/.claude/skills/add-worktree` already exists, move it aside first, or
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

### Claude configuration

These are copied from the main checkout, when they exist:

- `.claude/` (except `.claude/worktrees/`)
- `CLAUDE.md`
- `CLAUDE.local.md`
- `.mcp.json`
- `.worktreeinclude`

`.worktreeinclude` is only copied. The script does not copy the files that its
patterns list.

### Rerunning

Running it again for an existing worktree only copies missing files. It does not
fetch or change the branch.

## Safety

- Never overwrites an existing file in the worktree.
- Never uses `--force` and never deletes anything.
- Stops if the target folder is used by something else, or if the branch is
  checked out in another folder.
- Does not copy files into a symlinked folder in the worktree.
- Never prints file contents.

### Secrets

`.mcp.json`, `CLAUDE.local.md` and files under `.claude/` may contain secrets.
The script warns about each copied file that Git does not ignore. Add the
private ones to your `.gitignore`, for example:

```gitignore
CLAUDE.local.md
.claude/settings.local.json
.claude/worktrees/
# Only if it holds secrets:
.mcp.json
```

## Removing a worktree

The script never removes worktrees. When you are done:

```bash
git worktree remove ../my-app_feature-login
```

Git refuses if the worktree has modified or untracked files, which can include
copied files that are not ignored. Check them before deciding what to do.

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
```
