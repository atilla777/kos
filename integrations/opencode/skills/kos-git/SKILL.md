---
name: kos-git
description: Use ONLY for explicit Git repository operations such as git status, diff, history, branches, commits, merge, or push; not for an ordinary request to edit code.
---

# Work with Git in the current project

Read the project's `AGENTS.md` and other applicable instructions before acting. Follow its branch, review, test, commit and publication rules; this skill does not authorize publication. Identify the repository and current branch, inspect `git status`, relevant `git diff` (including staged changes), and `git log --oneline -10` before committing or integrating work. Treat unfamiliar files, untracked files and changes as someone else's work until investigated. Stage only intended files and inspect the staged diff; never commit secrets or runtime data.

Use the requested Git operation after checking its preconditions. For an unfamiliar operation or flag, consult the installed `git help`, `git help <command>` or `git <command> --help` before invoking it. The examples here are not a command allowlist. Prefer non-destructive operations and verify the resulting branch, status and diff. Do not discard changes, rewrite history, force-push, skip hooks or resolve a conflict by overwriting work. If a commit or hook fails, fix the problem and make a new commit rather than amending a failed one.

Commit, merge and push only when expressly requested by the user or required by the applicable project instructions for the assigned task. Before publication, check the target branch and remote, inspect all commits to be published and the diff against the destination; use the publication route specified by the project and the request, whether that is a reviewed local merge or a PR. Confirm the remote result, not just the local command's exit status. If history diverges, a conflict occurs, the branch is unexpected or push fails, stop the unsafe action and report the current state and the next safe step without changing unrelated work.

For GitHub PRs and checks, load `kos-github-cli` when the request calls for a GitHub operation. For a KOS development task load `kos-task-worktree` and follow the target project's publication rules; ordinary Git requests do not implicitly create task worktrees.
