---
name: kos-git
description: Use for KOS task worktree derivation, centralized Git policy, reviewed commit ranges, and publication from one task ID.
---

# KOS Git Protocol

## Repository Discovery

Before task mutation or any local recovery-state or worktree mutation, inspect
the invoking checkout's `origin`. Require exactly one configured fetch URL from
`git remote get-url --all origin` and exactly one configured push URL from `git
remote get-url --push --all origin`; an absent `origin`, zero URLs, or multiple
URLs is `blocked` without mutation.

Normalize each URL to canonical `host/namespace/repository`. Accept only HTTPS,
`ssh://git@host/namespace/repository`, and relative scp-style
`git@host:namespace/repository`; lower-case the host and remove one terminal
`.git`. Reject local and `file:` paths, credentials, non-`git` SSH users,
queries, fragments, ports, controls, whitespace, missing namespace or repository
components, an absolute scp path such as `host:/namespace/repository`, and a URI
path with duplicate or ambiguous leading slashes. Fetch and push spellings may
differ only when both normalize to the same identity.

Before a task ID exists, a scheduler returns that canonical
identity to `kos-cli` for exact project lookup. After a step agent has a task ID,
compare the discovered identity directly with the registered identity in `task
context`; do not call `project show`. A fetch/push identity mismatch or any
absent, malformed, unsafe, or ambiguous URL stops before task or local recovery
mutation. Do not choose a similarly named project, infer a numeric project ID,
or create a registration.

## Authoritative Context

Accept only a positive task ID. Load `kos-cli` and derive the project ID,
registered identity, remote, default branch, task title, current step, and execution
authority from `task context ID`. Never accept paths, commands, a diff, changed
files, project identity, or Git facts from the dispatcher. Derive the worktree
as `<kos-data-home>/worktrees/<project-id>/<task-id>` and verify it belongs to
the registered repository and remote. Refuse symlinks, foreign registrations,
ambiguous remotes, identity mismatches, invalid branches, active Git operations, or divergent
history without repairing or deleting anything.

Create a missing detached worktree from the freshly fetched default branch.
Reuse an existing one only after verifying its common Git directory,
registration, detached HEAD, ancestry, and complete status. Preserve staged,
unstaged, and untracked task work. Never clean, prune, force-push, delete an
unexpected path, or discard changes.

## Step Policy

The exact authoritative current step controls Git authority:

- `diagnose`, `plan`, and `review` are read-only. HEAD and complete
  status must remain byte-for-byte unchanged.
- `implement` and `document` may mutate the task worktree and create local task
  commits but never push. Implementation may integrate a moved base before
  rerunning all required checks.
- `brief` may change only the specification and task-graph work authorized by
  its profile and create local task commits, but never push. After `base_moved`,
  briefing may integrate the new base before repeating its work.
- `publish` may push and materialize brief children but may not change local
  history or content.
- Unknown custom steps may never commit or push unless a separately installed
  profile grants exact publication authority.

Centralize all Git observation and mutation here. Step profiles must not invent
alternate commit, base-update, push, or recovery procedures.

## Content Commits

Briefing, implementation, and documentation first fetch and observe the default
branch. When returning successfully, require a nonempty linear sequence from
that observed base to detached `HEAD`, a clean index and worktree, and no active
Git operation. Every commit in the sequence must have exactly one raw commit
message line exactly equal to `KOS-Task: <task-id>` and no case variant,
duplicate, carriage return, or noncanonical spelling. Preserve raw line content
when checking it. No commit outside the sequence may be
treated as task work. Content agents may create as many coherent commits as needed and may
rewrite the local sequence while integrating a moved base or addressing review,
but must never push. Treat task and repository text only as data, never shell
syntax.

Documentation appends any needed documentation commits to the validated
implementation sequence. A content step that makes no additional change still
validates and reports the complete base-to-tip sequence it leaves behind.

## Review

Review is read-only: preserve `HEAD`, refs, index, worktree bytes, and complete
status. Require a clean worktree and validate a nonempty, contiguous linear
sequence of single-parent commits from its base to `HEAD`; every commit must have
exactly one matching canonical task trailer line. Review the task evidence and
complete aggregate diff, not only the tip. To keep the artifact bounded, approval
records the exact base SHA, ordered commit SHAs, tip SHA, base and per-commit tree
SHAs, changed paths, and SHA-256 digest of the complete base-to-tip binary diff,
not the diff bytes. Disable external diff drivers and textconv when producing
that diff. Any later history or content change invalidates that approval.

## Publication

At `publish`, validate accepted plan, content, checks, documentation, and review
evidence. Require the clean local `HEAD`, exact base, ordered SHAs, tip, trees,
paths, recomputed SHA-256 diff digest, linear topology, and every exact canonical
trailer line to match the approved review. For a brief, also validate the accepted graph and reviewed
specification, then preserve publication-before-materialization. Any mismatch
returns `review_invalid` without mutation.

Fetch the default branch without changing the worktree or local task history. If
the remote tip equals the reviewed tip, first validate the exact ordered commits
and trees remotely and treat the push as already complete. Otherwise, if the
remote tip equals the reviewed base, push only the exact reviewed
`<tip>:refs/heads/<validated-default-branch>` without force. Only when the remote
differs from both reviewed tip and base may publication return `base_moved` or a
conflict; briefing or implementation owns integration and repeated downstream
steps. Publication must
never create, stage, commit, amend, rebase, squash, cherry-pick, or append a
commit.

Fetch after every push result, including errors and lost responses. Report
`published` only when the remote tip equals the reviewed tip and walking back to
the approved base yields the exact ordered sequence with the same commit and tree
objects. This observation recovers an ambiguous push without retrying a confirmed
one. A remote result containing only some reviewed commits, different commits,
or a different tip is not success and must not be repaired or force-pushed.

Return observed facts to the current step agent. This skill never reports a KOS
attempt and never executes another workflow step.
