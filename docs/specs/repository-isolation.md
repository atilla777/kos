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

The state service accepts only a task-derived branch and a lexically canonical absolute reservation path. It does not inspect that path or execute Git. The repository adapter remains responsible for filesystem canonicalization, symlink containment, Git common-directory identity, branch, HEAD, and cleanliness before an effect. Confirmation compares the adapter's common-directory digest with SHA-256 over the repository's persisted canonical UTF-8 common-directory path and records the observed HEAD.

After an expired attempt is reconciled, the next claim transfers an unresolved reservation's current owner and fencing token without changing its allocation or treating the worktree as confirmed. A clean reconciliation with an observed HEAD can confirm a reserved allocation. An absent observation leaves an unmaterialized reservation available for the owning attempt to reuse, and completes release only after materialization. Dirty and mismatched observations preserve the allocation and require explicit resolution; they never authorize adoption or removal.

## Git Ownership

`kos-repository` is the only skill allowed to perform mutating Git operations, including worktree creation or removal, commit, fetch, rebase, and push. The CLI persists and protects worktree reservations, publication intents, and generic commit/fetch/rebase intents but does not execute Git commands. During a workflow-step session, the generic executor may send an attempt-bound typed effect request to the lease-owning orchestrator. The orchestrator validates and durably prepares it, invokes `kos-repository`, reconciles its typed success, failure, or unknown observation, and returns that result before the executor finalizes its result manifest.

Before every operation, `kos-repository` validates repository identity, reservation, fencing token, expected branch and HEAD, and worktree cleanliness against the operation's preconditions. Detailed adapter requirements are defined by the [architecture rules](../rules/architecture.md).

Terminal cleanup is a separate idempotent two-phase operation. An observed clean worktree with its confirmed HEAD moves the reservation to `release_pending`; only a later `absent` observation atomically detaches it from the task and marks it `released`. A crash after removal is recovered by reconciling that absence. KOS never automatically removes a dirty or mismatched worktree, and released reservation history remains immutable while no longer occupying its active uniqueness keys.

[ADR-0004](../decisions/0004-task-git-protocol.md) records why KOS centralizes Git mutations and uses reservations.
