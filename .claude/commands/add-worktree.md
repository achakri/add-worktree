---
description: Create a Git worktree with the Claude Code configuration
argument-hint: <name>
---

Create a worktree with `scripts/add-worktree.sh`.

Requested name: `$ARGUMENTS`

1. If the requested name is empty, ask the user for it and wait for the answer.
   Do not invent one.
2. The name may contain only letters (A-Z, a-z), digits, `.`, `_`, `-` and `/`.
   If it contains anything else, including spaces or quotes, do not run any
   command. Say that the name is invalid and ask for another one. Do not
   correct it yourself.
3. Run the script from the main checkout, even if this session is in another
   worktree. Replace `NAME` with the validated name and keep the single quotes:

   ```bash
   main="$(git worktree list --porcelain | sed -n '1s/^worktree //p')" && cd "$main" && bash scripts/add-worktree.sh 'NAME'
   ```

4. If it succeeds, show the folder path, the number of files copied, all
   warnings, and the command to start Claude there.
5. If it fails, show the error message and stop. Do not work around it: do not
   retry with another name, run Git commands to change the repository, use
   `--force`, delete or move anything, or copy files yourself. You may suggest
   a fix, but let the user decide.

Never open or print the contents of the copied files, since they may contain
secrets.
