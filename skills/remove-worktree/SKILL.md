---
name: remove-worktree
description: Remove the current Git worktree, delete its local branch and end the terminal session
argument-hint: "[--force]"
disable-model-invocation: true
---

Remove the current worktree with the script bundled with this skill,
`${CLAUDE_SKILL_DIR}/scripts/remove-worktree.sh`.

Arguments: `$ARGUMENTS`

1. The only accepted argument is `--force`. If the arguments contain anything
   else, do not run any command; say that the command takes only `--force` and
   always removes the current worktree.
2. Run the script from the current folder. Add `--force` only if it is in the
   arguments above:

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/remove-worktree.sh"
   ```

   Set `REMOVE_WORKTREE_KEEP_SESSION=1` before `bash` only if the user asks to
   keep the session.
3. If it succeeds, report what was removed, the deleted branch and its commit,
   and all warnings, in a few lines. If the output says the session is closing,
   run nothing else: this session is about to end.
4. If it fails, show the error message and stop. Do not work around it: do not
   rerun with `--force`, commit, stash, push, merge, move or delete anything, or
   run Git commands to remove the worktree or branch yourself. You may suggest a
   fix, but let the user decide.

Never open or print the contents of configuration files such as `.env`, since
they may contain secrets.
