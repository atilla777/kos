---
name: kos-git
description: Use for KOS task worktree setup, Git publication, or recovery after an interrupted commit or push. Preserves uncommitted task work and verifies remote state before reporting publication.
---

# KOS Git Protocol

Use standard `git` commands directly. This skill owns Git observation and
mutation, but it does not own task state, workflow transitions, checks, review,
or Markdown artifacts. Never add a commit before the publication step.

## Inputs

Require all of these values from the orchestrator:

- positive decimal project and task IDs;
- the project's explicit `remote_url` and valid `default_branch`;
- the repository from which `/kos` was invoked;
- the current workflow step and whether it authorizes publication;
- the task number, title, and exact files belonging to the task
  when publishing or recovering publication.

Do not infer a missing value. A missing, invalid, or ambiguous input is
`blocked`.

## Paths

Resolve the KOS data home exactly as the application does:

1. Treat a missing or whitespace-only `KOS_DATA_HOME` as unset. Otherwise
   require it to be absolute and lexically normalize it like Ruby
   `File.expand_path` (including `.` and `..` components).
2. Otherwise, when `XDG_DATA_HOME` is absolute, lexically normalize it with the
   same `File.expand_path` semantics and append `/kos`.
3. Otherwise use `$HOME/.local/share/kos`.

Treat a whitespace-only or relative `XDG_DATA_HOME` as unset, matching the XDG
fallback used by the application. Reject a relative, nonblank `KOS_DATA_HOME`.
Derive, but never persist, the task worktree path as:

```text
<kos-data-home>/worktrees/<project-id>/<task-id>
```

IDs must contain only ASCII decimal digits and be greater than zero. Refuse a
path with a symlink below the trusted data home. Quote paths and refs in every
shell command.

## Verify The Repository

Observe the invoking checkout before changing anything:

```text
git rev-parse --is-inside-work-tree
git rev-parse --path-format=absolute --show-toplevel
git rev-parse --path-format=absolute --git-common-dir
git status --porcelain=v2 --untracked-files=all -z
git remote
git remote get-url --all <remote>
git remote get-url --push --all <remote>
git ls-remote --get-url <project-remote-url>
git check-ref-format --branch <default-branch>
```

Expand the project URL and each configured fetch and push URL with
`git ls-remote --get-url`. Select exactly one remote whose single fetch URL and
single push URL both exactly equal the expanded project URL. Do not guess that
different SSH and HTTPS spellings are equivalent. Do not print URLs containing
credentials.

Block if no remote or multiple remotes match, fetch and push destinations
differ, a URL is ambiguous, the branch is invalid, or repository identity
cannot be proved. Existing changes in the invoking checkout are allowed and
must remain untouched.

Fetch only the configured default branch, without tags or pruning:

```text
git fetch --no-tags <remote> refs/heads/<default-branch>:refs/remotes/<remote>/<default-branch>
git rev-parse --verify refs/remotes/<remote>/<default-branch>^{commit}
```

A failed or uncertain fetch is `blocked`; do not proceed from a stale
remote-tracking ref.

## Create Or Reuse A Worktree

Inspect `git worktree list --porcelain` before any filesystem mutation.

Create a worktree only if its derived path does not exist, is not registered,
and has no symlinked parent below the data home:

```text
git worktree add --detach <worktree-path> refs/remotes/<remote>/<default-branch>
```

After creation, verify its canonical top level and common Git directory, its
registration at exactly the derived path, detached HEAD, and HEAD equal to the
fetched base.

Reuse an existing worktree only when all of these facts are observable:

- the derived path exists and is not a symlink;
- exactly one worktree registration names its canonical path;
- its common Git directory equals the invoking repository's common directory;
- it has a valid detached HEAD;
- no merge, rebase, cherry-pick, revert, or bisect is in progress.

Compare its HEAD with the freshly fetched base. Normal task work may be based
on that commit or an older commit that
`git merge-base --is-ancestor <head> <fetched-base>` proves belongs to the same
forward-moving default-branch history. If fetched base is instead an ancestor
of HEAD, local commits exist: allow no work except publication recovery, where
the candidate rules below must verify them. If neither commit is an ancestor of
the other, history is divergent and reuse is `blocked` without mutation.

Do not require the task worktree to be clean. Preserve tracked, staged,
unstaged, and untracked task work exactly as found. Block without repairing when
the path is foreign, unregistered, missing despite registration, branch-bound,
locked without clear ownership, or otherwise ambiguous.

Never run `git worktree prune`, `git worktree remove`, `git clean`, or
`git reset --hard`. Never delete an unexpected path.

## Development, Checks, And Review

Keep all task changes uncommitted. Record the initial base SHA when the
worktree is created and observe HEAD and status before and after each step.
Development, checks, and review must not move HEAD. If a commit appears before
publication and it is not a valid interrupted publication candidate described
below, return `blocked`.

An agent may read and edit only the task worktree. It must not use the invoking
checkout as task working state. Checks inspect the uncommitted worktree, and
review is read-only.

## Publication Preflight

Reverify repository and worktree identity, then fetch the default branch again.
Observe:

```text
git -C <worktree-path> rev-parse HEAD
git -C <worktree-path> status --porcelain=v2 --untracked-files=all -z
git -C <worktree-path> rev-list --parents -n 1 HEAD
git -C <worktree-path> log -1 --format=%B
git rev-parse refs/remotes/<remote>/<default-branch>^{commit}
```

Check for unresolved entries and active Git operations. Classify the observed
state before mutating it. A network failure that prevents observing the remote
is `blocked`.

## A Moved Base

When HEAD is still the previous base, task changes are uncommitted, and the
fetched remote base moved, first require
`git merge-base --is-ancestor <previous-base> <new-base>` to prove a normal
forward move. Divergent or rewritten history is `blocked` without mutation.
Then:

1. Use `git reset --mixed HEAD` only if task changes are staged. This preserves
   working-tree contents while normalizing the index.
2. Run `git checkout --merge --detach <new-base-sha>`.
3. Re-observe HEAD, status, unmerged entries, and untracked files.
4. Return `base_moved` without committing or pushing.

Compatible changes must remain uncommitted on the new base. Preserve visible
conflicts for development; do not resolve or discard them. If checkout refuses
without moving HEAD, report the exact obstruction as `blocked`. Checks and an
independent review must run again after every `base_moved`.

Do not use stash: it creates hidden commit objects and complicates recovery.

## Create The Publication Commit

Proceed only when the current HEAD equals the freshly fetched remote base, the
reviewed task diff is non-empty, no unresolved entry exists, and every changed
path is confirmed to belong to this task.

Stage only the confirmed task files. Inspect the complete staged diff and run
`git diff --cached --check`. Require no remaining unstaged or untracked task
content. Create exactly one commit with the task number in its subject and one
machine-recognizable trailer. Derive `<subject-title>` deterministically by
replacing every run of title whitespace, including newlines, with one ASCII
space and trimming leading and trailing whitespace. Omit the colon and title
when that result is empty:

```text
KOS task <task-id>: <subject-title>

KOS-Task: <task-id>
```

Verify that the new commit has exactly one parent, its parent is the fetched
base, its subject exactly matches the generated task subject, it contains
exactly one matching `KOS-Task` trailer, its changed paths exactly match the
confirmed task files, its full patch is the reviewed task change, its tree
differs from its parent, and the worktree is clean. Do not amend or create a
second commit.

## Push And Verify

Push the exact detached commit to the configured default branch:

```text
git -C <worktree-path> push --porcelain <remote> <commit-sha>:refs/heads/<default-branch>
```

Never use force push, `--force-with-lease`, or a `+` refspec. Regardless of the
push exit status or output, fetch the exact default branch again before deciding
whether to retry or report an outcome.

Publication is confirmed when the candidate equals the observed remote tip or
`git merge-base --is-ancestor <candidate-sha> <remote-sha>` proves that the
candidate is already in remote history. Only then return `published`.

If the candidate is absent, its parent still equals the observed remote tip,
and the previous push is proven to have had no effect, one normal push retry is
safe. If remote state cannot be observed, do not retry; return `blocked`.

## Recover An Interrupted Publication

Always observe local and remote state before mutation.

- Staged but uncommitted changes are still task work. If base is unchanged,
  verify the complete diff and continue with the single commit. If base moved,
  unstage without discarding content, update to the new base, and return
  `base_moved`.
- A local commit is a recoverable candidate only after repeating every commit
  verification from the preceding section: clean worktree, one expected parent,
  exact generated subject, one matching trailer, exact task-owned changed paths,
  non-empty tree change, and full patch inspection against the task being
  published. A trailer alone never proves ownership or review. If any fact
  cannot be re-established, return `blocked` or send the uncommitted work
  through checks and review again; never push the uncertain commit.
- If remote already contains a fully verified candidate, return `published`.
  If its parent equals the remote tip, push that same commit rather than creating
  another.
- If a valid unpublished candidate's parent is no longer the remote tip, run
  `git merge-base --is-ancestor <candidate-parent> <remote-tip>` first. Only a
  proven forward move may continue: run `git reset --mixed <candidate-parent>`
  to restore its tree as uncommitted changes, update to the new base with
  `git checkout --merge --detach`, and return `base_moved` so checks and review
  repeat. If ancestry fails, treat remote history as rewritten and return
  `blocked` without reset or checkout.
- A merge commit, multiple local task commits, a wrong or duplicate trailer,
  extra changes on top of a candidate, rewritten remote history, or uncertain
  ancestry is `blocked` without cleanup.

## Result

Return observed facts to the calling `kos-step`: worktree path, pre- and post-action
HEAD, fetched base SHA, candidate SHA when one exists, observed remote SHA, the
result (`ready`, `base_moved`, `published`, or `blocked`), and a precise reason
for a blocker. The calling step writes the artifact and the orchestrator reports
the workflow outcome; this skill does neither.
