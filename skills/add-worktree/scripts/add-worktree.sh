#!/usr/bin/env bash
#
# Usage: add-worktree.sh <name>
#
# Creates the Git worktree ../<project>_<name> on branch <name> and copies the
# Claude Code configuration from the main checkout into it. Rerunning it for an
# existing worktree only copies missing files. Then opens a new terminal tab
# running Claude there, unless ADD_WORKTREE_NO_TAB=1.
#
# Works with Bash 3.2 (macOS). Never uses --force and never deletes anything.

set -euo pipefail

# Ignore Git overrides inherited from hooks or other tools, so that
# "git -C <folder>" really operates on that folder.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

usage="Usage: add-worktree.sh <name>"
warnings=()
copied=0

# Records a warning once.
warn() {
  local w
  if [ "${#warnings[@]}" -gt 0 ]; then
    for w in "${warnings[@]}"; do
      [ "$w" != "$1" ] || return 0
    done
  fi
  warnings[${#warnings[@]}]=$1
}

print_warnings() {
  [ "${#warnings[@]}" -gt 0 ] || return 0
  echo "Warnings:"
  printf '  - %s\n' "${warnings[@]}"
}

die() {
  print_warnings >&2
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

valid_name() {
  local LC_ALL=C
  case $1 in
    *[!A-Za-z0-9._/-]*) return 1 ;;
    -* | HEAD | refs/*) return 1 ;;
  esac
  git check-ref-format "refs/heads/$1"
}

real_dir() {
  (cd -- "$1" 2>/dev/null && pwd -P)
}

# Prints the shared Git directory of the checkout in folder $1.
common_dir_of() {
  (cd -- "$1" 2>/dev/null &&
    dir=$(git rev-parse --git-common-dir 2>/dev/null) &&
    cd -- "$dir" && pwd -P)
}

# True if exactly this ref exists (case-sensitive, even on macOS).
ref_exists() {
  local found
  found=$(git for-each-ref --format='%(refname)' "$1")
  grep -Fxq -- "$1" <<<"$found"
}

# Prints the folder where branch $1 is checked out, if any.
branch_folder() {
  git worktree list --porcelain | awk -v ref="branch refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == ref && !seen { print path; seen = 1 }'
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Opens a new tab in the current terminal and runs the shell command $1 in it.
# On failure, prints the reason and returns non-zero.
open_tab() {
  local pane

  # tmux comes first: it runs inside another terminal. Its windows are its tabs.
  if [ -n "${TMUX:-}" ]; then
    pane=$(tmux new-window -P -F '#{pane_id}') &&
      tmux send-keys -t "$pane" -l "$1" &&
      tmux send-keys -t "$pane" Enter
    return
  fi

  # The command is passed as an argument, never pasted into the AppleScript.
  case ${TERM_PROGRAM:-} in
    Apple_Terminal)
      # Terminal cannot create a tab by script, so press Command-T, then run
      # the command only in a tab that did not exist before.
      osascript - "$1" <<'APPLESCRIPT'
on terminalTTYs()
  set ttyList to {}
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        try
          set end of ttyList to (tty of t as text)
        end try
      end repeat
    end repeat
  end tell
  return ttyList
end terminalTTYs

on run argv
  set oldTTYs to my terminalTTYs()
  tell application "Terminal" to activate
  delay 0.3
  tell application "System Events"
    set frontName to name of first process whose frontmost is true
    if frontName is not "Terminal" then error "Terminal is not the frontmost application"
    keystroke "t" using command down
  end tell
  repeat 30 times
    delay 0.1
    tell application "Terminal"
      repeat with w in windows
        repeat with t in tabs of w
          try
            set newTTY to (tty of t as text)
          on error
            set newTTY to ""
          end try
          if newTTY is not "" and oldTTYs does not contain newTTY then
            do script (item 1 of argv) in t
            return
          end if
        end repeat
      end repeat
    end tell
  end repeat
  error "no new tab appeared"
end run
APPLESCRIPT
      ;;
    iTerm.app)
      osascript - "$1" <<'APPLESCRIPT'
on run argv
  tell application id "com.googlecode.iterm2"
    tell current window
      set newTab to (create tab with default profile)
      tell current session of newTab to write text (item 1 of argv)
    end tell
  end tell
end run
APPLESCRIPT
      ;;
    *)
      echo "not supported in this terminal (${TERM_PROGRAM:-unknown})"
      return 1
      ;;
  esac
}

# Copies one file or symlink, given relative to the main checkout.
copy_item() {
  local rel=$1
  local src="$main_root/$1" dest="$target/$1"
  local dir=$target rest=$1 shown link

  # Never write through a symlink: it could lead outside the worktree.
  while [[ $rest == */* ]]; do
    dir="$dir/${rest%%/*}"
    rest=${rest#*/}
    if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
      shown=${dir#"$target"/}
      warn "skipped files under $shown: it is a symlink or a file in the worktree"
      return 0
    fi
  done

  # Never overwrite. A dangling symlink counts as existing.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    return 0
  fi

  mkdir -p -- "${dest%/*}" || die "could not create the folder for $rel"
  if [ -L "$src" ]; then
    link=$(readlink "$src") || die "could not read the link $rel"
    ln -s -- "$link" "$dest" || die "could not copy the link $rel"
    [ -e "$dest" ] || warn "copied link points to a missing target: $rel"
  else
    cp -p -- "$src" "$dest" ||
      die "could not copy $rel (check for a partial file before rerunning)"
  fi
  copied=$((copied + 1))

  if ! git -C "$target" check-ignore --quiet -- "$rel"; then
    warn "copied but not ignored by Git (do not commit secrets): $rel"
  fi
}

# --- Arguments ---------------------------------------------------------------

[ $# -eq 1 ] || die "expected exactly one argument. $usage"
name=$1
[ -n "$name" ] || die "the name is empty. $usage"
valid_name "$name" ||
  die "invalid name '$name'. Use letters, digits, '.', '_', '-' and '/', forming a valid Git branch name."

# --- Main checkout and target folder -----------------------------------------

[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] ||
  die "run this from inside a Git checkout."

common_dir=$(common_dir_of .) || die "cannot locate the Git directory."
if [ "$(real_dir "$(git rev-parse --git-dir)")" = "$common_dir" ]; then
  main_root=$(git rev-parse --show-toplevel)
else
  # In a linked worktree: Git always lists the main checkout first.
  main_root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
fi
if [ "$(common_dir_of "$main_root")" != "$common_dir" ] ||
  [ "$(git -C "$main_root" rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
  die "cannot find the main checkout (bare repository or separate Git directory?)."
fi
main_root=$(real_dir "$main_root")

project=${main_root##*/}
target="${main_root%/*}/${project}_${name//\//-}"

rerun=no
if [ -e "$target" ] || [ -L "$target" ]; then
  if [ -L "$target" ] || [ ! -d "$target" ]; then
    die "target is used by something else (a file or symlink): $target"
  fi
  if [ -e "$target/.git" ] && [ "$(common_dir_of "$target")" = "$common_dir" ]; then
    current=$(git -C "$target" symbolic-ref --quiet HEAD || true)
    [ "$current" = "refs/heads/$name" ] ||
      die "target is already a worktree on ${current:-a detached HEAD}, not on branch '$name': $target"
    rerun=yes
  else
    contents=$(ls -A "$target") || die "cannot read the target folder: $target"
    [ -z "$contents" ] || die "target folder is used by something else: $target"
  fi
fi

# --- Branch and worktree -----------------------------------------------------

if [ "$rerun" = no ]; then
  holder=$(branch_folder "$name")
  if [ -n "$holder" ]; then
    if [ -d "$holder" ] && [ "$holder" != "$target" ]; then
      die "branch '$name' is already checked out in a different folder: $holder"
    fi
    die "Git still registers branch '$name' at $holder, but that worktree is missing. Check it, then run 'git worktree prune'."
  fi

  local_ref="refs/heads/$name"
  tracking="refs/remotes/origin/$name"
  has_origin=no
  on_origin=no
  listing=

  if git remote get-url origin >/dev/null 2>&1; then
    has_origin=yes
    git fetch --quiet --no-prune origin ||
      die "fetching from origin failed; no worktree was created."
    listing=$(git ls-remote --symref origin HEAD "$local_ref") ||
      die "could not list the branches on origin; no worktree was created."

    # Ask origin itself: a tracking ref may be left over from a deleted branch.
    if awk -F '\t' -v ref="$local_ref" '$2 == ref { f = 1 } END { exit !f }' <<<"$listing"; then
      ref_exists "$tracking" ||
        die "origin has branch '$name' but fetch did not download it (single-branch clone?). Check remote.origin.fetch."
      on_origin=yes
    elif ref_exists "$tracking"; then
      warn "ignored origin/$name: that branch no longer exists on origin"
    fi
  fi

  if ref_exists "$local_ref"; then
    git worktree add --quiet "$target" "$name" ||
      die "git worktree add failed (see the message above)."
    if [ "$on_origin" = yes ]; then
      if git merge-base --is-ancestor "$local_ref" "$tracking"; then
        git -C "$target" merge --quiet --ff-only "$tracking" >&2 ||
          warn "could not fast-forward '$name' from origin; using it as it is"
      elif ! git merge-base --is-ancestor "$tracking" "$local_ref"; then
        warn "'$name' has diverged from origin/$name; using the local branch unchanged"
      fi
    fi
  elif [ "$on_origin" = yes ]; then
    git worktree add --quiet --track -b "$name" "$target" "$tracking" ||
      die "git worktree add failed (see the message above)."
  else
    base=
    if [ "$has_origin" = yes ]; then
      default=$(awk -F '\t' '$2 == "HEAD" && sub(/^ref: refs\/heads\//, "", $1) { print $1 }' <<<"$listing")
      if [ -z "$default" ]; then
        default=$(git symbolic-ref --quiet refs/remotes/origin/HEAD || true)
        default=${default#refs/remotes/origin/}
      fi
      if [ -n "$default" ] && ref_exists "refs/remotes/origin/$default"; then
        base="refs/remotes/origin/$default"
      else
        warn "origin's default branch is unavailable; created '$name' from HEAD"
      fi
    fi
    if [ -z "$base" ]; then
      base=$(git rev-parse --verify --quiet 'HEAD^{commit}') ||
        die "there is no commit to start from. Make a first commit, then retry."
    fi
    git worktree add --quiet --no-track -b "$name" "$target" "$base" ||
      die "git worktree add failed (see the message above)."
  fi
fi

# --- Claude configuration ----------------------------------------------------

if [ -d "$main_root/.claude" ]; then
  # -H follows .claude itself if it is a symlink. An empty record means that
  # find failed.
  while IFS= read -r -d '' file; do
    if [ -n "$file" ]; then
      copy_item "$file"
    else
      warn "some files under .claude could not be read and were not copied"
    fi
  done < <(cd -- "$main_root" &&
    find -H .claude -path .claude/worktrees -prune -o \( -type f -o -type l \) -print0 ||
    printf '\0')
elif [ -e "$main_root/.claude" ] || [ -L "$main_root/.claude" ]; then
  warn "skipped .claude: it is not a folder or is a broken link"
fi

for item in CLAUDE.md CLAUDE.local.md .mcp.json .worktreeinclude; do
  if [ -f "$main_root/$item" ] || [ -L "$main_root/$item" ]; then
    copy_item "$item"
  fi
done

# --- New tab -----------------------------------------------------------------

claude_command="cd $(shell_quote "$target") && claude"
tab_opened=no
if [ "${ADD_WORKTREE_NO_TAB:-}" != 1 ]; then
  # A failure here is only a warning: the worktree is ready.
  if reason=$(open_tab "$claude_command" 2>&1); then
    tab_opened=yes
  else
    case $reason in
      *1002* | *"not allowed"*)
        reason="$reason Allow your terminal in System Settings > Privacy & Security > Accessibility."
        ;;
      *-1743* | *"Not authorized"*)
        reason="$reason Allow your terminal in System Settings > Privacy & Security > Automation."
        ;;
    esac
    warn "could not open a new tab: ${reason//$'\n'/ }"
  fi
fi

# --- Summary -----------------------------------------------------------------

echo "Worktree: $target"
echo "Files copied: $copied"
if [ "${#warnings[@]}" -gt 0 ]; then
  print_warnings
else
  echo "Warnings: none"
fi
if [ "$tab_opened" = yes ]; then
  echo "New tab: opened, starting Claude"
fi
echo "Start Claude with:"
printf '  %s\n' "$claude_command"
