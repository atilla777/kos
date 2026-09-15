---
title: Declared Base-Movement Recovery
status: accepted
date: 2026-09-15
---

# ADR-0012: Declared Base-Movement Recovery

## Context

A publication can become safely superseded when its immediate push preflight proves that the trusted base moved after durable preparation. The reviewed candidate must not be pushed or reused, but an immutable pinned workflow still owns the task's legal state transitions and repository-effect capabilities.

The published `quick-fix@1.0.1` graph has no recovery edge from publication and its development status authorizes a commit rather than trusted-base synchronization. Changing that published definition or moving a task outside its pinned graph would make execution irreproducible.

## Decision

Base movement is recovered through an explicit transition in a new immutable workflow version. `quick-fix@1.0.2` declares `publication -> base-synchronization -> review`. A specialized idempotent operation may take the recovery edge only after revalidating the durable moved-base publication and current leased attempt; it records no fabricated publication artifact.

The dedicated synchronization status authorizes one trusted fetch followed by one verified rebase. One additive version 2 mutation verifies canonical rebase and post-rebase clean-observation evidence and atomically records rebase success with the durable worktree HEAD. If its owner is interrupted before step completion, the replacement performs its own trusted fetch and verified no-op rebase; unchanged reconciliation is authorized only by the latest complete durable pair from an earlier interrupted attempt at the same HEAD. That HEAD becomes a new candidate only after fresh checks. Candidate-specific tests, review, and publication evidence from the superseded SHA remain historical and cannot satisfy the new generation.

Tasks remain pinned to their original workflow version. KOS does not migrate tasks from `quick-fix@1.0.1`; that version remains fail-closed at this recovery boundary.

## Consequences

- Recovery remains reproducible from the task's immutable workflow graph and durable publication evidence.
- Ordinary development after review changes remains separate from base synchronization.
- A rebase conflict, failed effect, unknown result, or unsynchronized HEAD cannot create a candidate generation.
- New quick-fix tasks use `1.0.2`; older pinned tasks require an explicit future migration decision if they must recover automatically.

## Rejected Alternatives

### Mutate quick-fix@1.0.1

Changing published content would violate workflow immutability and would not update existing catalog records safely.

### Move the task outside its pinned graph

A server-only exception would make task state disagree with the immutable workflow version that authorizes transitions and capabilities.

### Reuse development for synchronization

Development's commit contract also handles review changes. Making it conditionally authorize fetch and rebase would couple unrelated recovery paths and make a single frozen context unable to safely support both rebase and a later worktree-bound commit.
