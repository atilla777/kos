---
title: KOS Repository Isolation
status: active
---

# KOS Repository Isolation

## Repository Scope

One central KOS installation may serve multiple Git repositories. Every repository-owned record and operation is scoped by immutable `repository_id`. The API resolves and authorizes that scope before mutation and never trusts a supplied filesystem path as the sole proof of identity. Registration independently verifies the canonical Git common directory and trusted publication settings and is defined by [Central Persistence](central-persistence.md). [ADR-0001](../decisions/0001-central-rest-api.md) owns the multi-repository architecture rationale.

## Task Isolation

Every task whose workflow changes repository files uses a dedicated branch derived from its repository-specific public number, such as `kos/task-KOS-000123`, a dedicated Git worktree, and a worktree allocation recorded in task state.

Allocation is a recoverable protocol:

1. The CLI atomically reserves a unique canonical branch name and worktree path with the active attempt's fencing token.
2. `kos-repository` materializes only that reservation.
3. The CLI confirms allocation after verifying repository identity, Git common directory, branch, and canonical path.

An incomplete reservation is reconciled after lease expiry. An existing worktree cannot be adopted without proof that it belongs to the same reservation.

## Git Ownership

`kos-repository` is the only skill allowed to perform mutating Git operations, including worktree creation or removal, commit, fetch, rebase, and push. The CLI stores and protects reservations but does not execute Git commands. Capability skills prepare file changes or workflow decisions and return requested Git effects in their result manifests; only the lease-owning orchestrator invokes `kos-repository`.

Before every operation, `kos-repository` validates repository identity, reservation, fencing token, expected branch and HEAD, and worktree cleanliness against the operation's preconditions. Detailed adapter requirements are defined by the [architecture rules](../rules/architecture.md).

Terminal cleanup is a separate idempotent operation. KOS never automatically removes a dirty or unknown worktree.

[ADR-0004](../decisions/0004-task-git-protocol.md) records why KOS centralizes Git mutations and uses reservations.
