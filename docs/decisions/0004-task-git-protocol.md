---
title: Task Git Protocol
status: accepted
date: 2026-09-08
---

# ADR-0004: Task Git Protocol

## Context

Multiple agents may change and publish repositories concurrently. Git worktrees and pushes are external effects that cannot share a SQLite transaction, and an interrupted operation may leave allocation or remote state different from the last recorded KOS state.

## Decision

Every repository-changing task uses a reserved branch and dedicated worktree. Allocation is a durable reserve, materialize, verify, and confirm protocol bound to repository identity, attempt, lease, and fencing token.

Only `kos-repository` performs mutating Git commands. The owning orchestrator requests those operations after validating the active reservation and expected repository state. Publication records intent, publishes the independently reviewed candidate SHA by fast-forward only, fetches the trusted remote, and records observed reachability before workflow completion. Unknown outcomes are reconciled before retry.

The observable contracts are defined in [Repository Isolation](../specs/repository-isolation.md) and [Publication](../specs/publication.md).

## Consequences

- Capability skills and the CLI do not issue mutating Git commands.
- Reservations, cleanup, and publication are explicit idempotent protocols rather than incidental filesystem operations.
- Base-branch movement creates a new candidate and invalidates candidate-specific evidence from the old generation.
- Force-push and automatic deletion of dirty or unknown worktrees are prohibited.

## Rejected Alternatives

### Let each capability skill run Git

Distributed Git ownership makes reservation, fencing, validation, and recovery inconsistent.

### Share one checkout among tasks

Concurrent tasks can overwrite each other's files, index, branch, and HEAD.

### Merge or force-push automatically after base movement

This would publish a commit other than the reviewed candidate or rewrite shared history without a new review generation.
