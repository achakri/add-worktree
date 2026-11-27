#!/usr/bin/env bash
#
# Usage: remove-worktree.sh [--force]
#
# Removes the linked worktree it is run from, deletes its local branch, then
# ends the terminal session, unless REMOVE_WORKTREE_KEEP_SESSION=1.
#
# Without --force, it changes nothing if that would lose uncommitted changes,
# changed configuration files or commits. It never removes the main checkout,
# deletes the default branch or deletes anything on origin.
#
# Works with Bash 3.2 (macOS).

set -euo pipefail

# Ignore Git overrides inherited from hooks or other tools.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

usage="Usage: remove-worktree.sh [--force]"
# Gives Claude time to report the result before its session ends.
close_delay=${REMOVE_WORKTREE_CLOSE_DELAY:-8}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$1"
}

real_dir() {
  (cd -- "$1" 2>/dev/null && pwd -P)
}

# Prints the terminal device of this process or of its nearest parent that has
# one. Claude Code runs commands without a terminal, but is itself in one.
session_tty() {
  local pid=$$ tty
  while [ "${pid:-0}" -gt 1 ]; do
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    case $tty in
      '' | '?'*) ;;
      *)
        echo "$tty"
        return 0
        ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  return 1
}

# Ends every process on terminal $1, except the one with ID $2.
end_processes() {
  local pid
  for pid in $(ps -t "$1" -o pid= 2>/dev/null); do
    [ "$pid" = "$2" ] || kill -HUP "$pid" 2>/dev/null || true
  done
  sleep 2
  for pid in $(ps -t "$1" -o pid= 2>/dev/null); do
    [ "$pid" = "$2" ] || kill -KILL "$pid" 2>/dev/null || true
  done
}

# Closes the tab of terminal $1 in macOS Terminal, once its processes ended.
# Terminal cannot close a tab by script, so select it and press Command-W, only
# if it is still the selected tab of the front window.
close_apple_tab() {
  osascript - "/dev/$1" <<'APPLESCRIPT'
on run argv
  set wanted to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        try
          if (tty of t as text) is wanted then
            set selected tab of w to t
            set index of w to 1
            activate
            delay 0.3
            if (tty of selected tab of front window as text) is not wanted then return
            tell application "System Events"
              if name of first process whose frontmost is true is not "Terminal" then return
              keystroke "w" using command down
            end tell
            return
          end if
        end try
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}

close_iterm_session() {
  osascript - "/dev/$1" <<'APPLESCRIPT'
on run argv
  tell application id "com.googlecode.iterm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if (tty of s as text) is (item 1 of argv) then
            tell s to close
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}

# Ends the session on terminal $1 after a delay.
close_session() {
  local self
  sleep "$close_delay"
  # tmux comes first: it runs inside another terminal. Only this pane is closed.
  if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    tmux kill-pane -t "$TMUX_PANE"
    return
  fi
  self=$(sh -c 'echo $PPID')
  end_processes "$1" "$self"
  case ${TERM_PROGRAM:-} in
    Apple_Terminal) close_apple_tab "$1" ;;
    iTerm.app) close_iterm_session "$1" ;;
  esac
}

# --- Arguments ---------------------------------------------------------------

force=no
case $# in
  0) ;;
  1)
    [ "$1" = --force ] || die "unknown argument '$1'. $usage"
    force=yes
    ;;
  *) die "too many arguments. $usage" ;;
esac

# --- Current worktree --------------------------------------------------------

[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] ||
  die "run this from inside the worktree to remove."

root=$(real_dir "$(git rev-parse --show-toplevel)")
git_dir=$(real_dir "$(git rev-parse --git-dir)")
common_dir=$(real_dir "$(git rev-parse --git-common-dir)")
[ "$git_dir" != "$common_dir" ] ||
  die "this is the main checkout, which is never removed. Run this from a linked worktree."

# Git always lists the main checkout first.
main_root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
main_root=$(real_dir "$main_root") &&
  [ "$(git -C "$main_root" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] ||
  die "cannot find the main checkout (bare repository or separate Git directory?)."

branch=$(git symbolic-ref --quiet HEAD) ||
  die "this worktree has a detached HEAD, so there is no branch to delete."
branch=${branch#refs/heads/}
tip=$(git rev-parse --verify --quiet 'HEAD^{commit}') ||
  die "branch '$branch' has no commit."

# Removing this folder would also remove any worktree inside it.
nested=$(git worktree list --porcelain |
  awk -v prefix="worktree $root/" 'index($0, prefix) == 1 { print substr($0, 10) }')
[ -z "$nested" ] ||
  die "another worktree is inside this one; remove it first: $nested"

# --- Origin ------------------------------------------------------------------

listing=
default=
if git remote get-url origin >/dev/null 2>&1; then
  if git fetch --quiet --no-prune origin &&
    listing=$(git ls-remote --symref origin HEAD 'refs/heads/*'); then
    default=$(awk -F '\t' '$2 == "HEAD" && sub(/^ref: refs\/heads\//, "", $1) { print $1 }' <<<"$listing")
  else
    listing=
    warn "could not reach origin; checked local branches only"
  fi
  if [ -z "$default" ]; then
    default=$(git symbolic-ref --quiet refs/remotes/origin/HEAD || true)
    default=${default#refs/remotes/origin/}
  fi
fi

case $branch in
  main | master | "$default")
    die "'$branch' is a default branch, which is never deleted."
    ;;
esac

# --- Nothing would be lost ---------------------------------------------------

if [ "$force" = no ]; then
  changes=$(git -C "$root" status --porcelain --untracked-files=all --ignore-submodules=none) ||
    die "could not check for uncommitted changes."
  [ -z "$changes" ] ||
    die "there are uncommitted or untracked files:
$changes
Nothing was removed. Commit or move them, or rerun with --force to discard them."

  # Git removes ignored files without asking. Protect the configuration files
  # that exist only here or differ from the main checkout.
  changed=
  while IFS= read -r -d '' file; do
    file=${file#./}
    [ -n "$file" ] || die "could not read all the configuration files."
    git -C "$root" check-ignore --quiet -- "$file" || continue
    if [ -L "$root/$file" ]; then
      [ -L "$main_root/$file" ] &&
        [ "$(readlink "$root/$file")" = "$(readlink "$main_root/$file")" ] &&
        continue
    else
      cmp -s -- "$root/$file" "$main_root/$file" && continue
    fi
    changed="$changed
  $file"
  done < <(
    cd -- "$root" || exit
    for item in CLAUDE.md CLAUDE.local.md .mcp.json .worktreeinclude .env; do
      if [ -f "$item" ] || [ -L "$item" ]; then
        printf '%s\0' "$item"
      fi
    done
    if [ -e .claude ] || [ -L .claude ]; then
      find .claude -path .claude/worktrees -prune -o \( -type f -o -type l \) -print0 ||
        printf '\0'
    fi
  )
  [ -z "$changed" ] ||
    die "these ignored files are new or differ from the main checkout:$changed
Nothing was removed. Copy what you need, or rerun with --force to discard them."

  # The commits must remain on another local branch or on origin.
  saved=no
  others=$(git for-each-ref --contains "$tip" --format='%(refname)' refs/heads/)
  if grep -Fxvq -- "refs/heads/$branch" <<<"$others"; then
    saved=yes
  else
    while IFS=$'\t' read -r sha ref; do
      case $ref in
        refs/heads/*) ;;
        *) continue ;;
      esac
      if git merge-base --is-ancestor "$tip" "$sha" 2>/dev/null; then
        saved=yes
        break
      fi
    done <<<"$listing"
  fi
  [ "$saved" = yes ] ||
    die "branch '$branch' has commits that are on no other branch, locally or on origin.
Nothing was removed. Push or merge it, or rerun with --force to discard them.
A squash or rebase merge also looks like this."
fi

# --- Remove ------------------------------------------------------------------

tty=$(session_tty) || tty=

cd -- "$main_root"
if [ "$force" = yes ]; then
  git worktree remove --force "$root" ||
    die "git worktree remove failed (see the message above)."
else
  git worktree remove "$root" ||
    die "git worktree remove failed (see the message above)."
fi
echo "Removed worktree: $root"

# -D is safe here: the checks above replace the one done by -d, which depends on
# what the main checkout has checked out.
git branch --quiet -D "$branch" ||
  die "the worktree was removed, but branch '$branch' could not be deleted."
echo "Deleted branch: $branch (was $tip)"
echo "Main checkout: $main_root"

# --- Terminal session --------------------------------------------------------

if [ "${REMOVE_WORKTREE_KEEP_SESSION:-}" = 1 ]; then
  echo "Terminal session: kept"
elif [ -z "$tty" ]; then
  warn "no terminal session found; close this session yourself"
else
  (
    trap '' HUP
    close_session "$tty"
  ) </dev/null >/dev/null 2>&1 &
  echo "Terminal session: closing in $close_delay seconds ($tty)"
fi
