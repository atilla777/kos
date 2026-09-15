---
title: Immutable Publication Result Handoff
status: accepted
date: 2026-09-15
---

# ADR-0013: Immutable Publication Result Handoff

## Context

A publication attempt can durably reconcile canonical push evidence proving that its reviewed candidate is reachable, then receive a successful child result before worktree cleanup. Cleanup is intentionally recoverable and may cross attempt ownership, but the exact child manifest previously existed only in orchestration memory. An interruption before release completed could therefore leave durable publication evidence and cleanup state without the result needed by a later terminal-completion boundary.

The mutable publication intent is evidence about the Git side effect, while a `WorkflowAttempt` remains started until its workflow transition. Storing the child result in either would conflate lifecycles and permit replacement ownership to obscure who produced the manifest. Repeating the child or push after interruption would also violate the existing reconciliation model.

## Decision

KOS records a separate immutable `PublicationResult` after reachable push reconciliation and before publication worktree cleanup. The record preserves the exact succeeded child manifest, original producing attempt and frozen input-context digest, and an immutable snapshot binding the repository, task, publication, reviewed candidate generation, trusted target, approved review, passed checks, and canonical reachable push evidence. The server reconstructs and verifies the canonical push evidence and recomputes its digest at the persistence boundary.

Only the original live lease-owning producer may create the result. One publication has at most one result, enforced under concurrency, and idempotent replay returns it. The recovery guarantee starts after the recording transaction commits; no guarantee is made for a child result lost before that boundary.

A replacement publication attempt may retrieve the result without the producer's idempotency key and use its own current lease and fencing token only to authorize conservative cleanup. Producer attribution, context, manifest, and evidence never transfer or change. Application policy and a database invariant both prevent the publication reservation from entering `release_pending` until the result exists. Existing clean, dirty, mismatched, absent, removal, and release reconciliation rules remain authoritative.

The result does not authorize another push and is not itself a task artifact or workflow transition. Recording and retrieval do not implement `publication.complete`, register publication evidence, complete an attempt, or move a task to `completed`. The operations are additive version 2 commands; version 1 schemas and published workflow definitions remain unchanged.

## Consequences

- Cleanup can recover across attempt replacement without repeating the child result or Git push.
- Terminal completion can later consume one stable producer-attributed manifest and evidence snapshot.
- A crash before result recording commits still requires explicit recovery because no durable manifest exists.
- Dirty or mismatched worktrees remain allocated and pending even when a publication result exists.
- Persistence must enforce both immutability and the result-before-`release_pending` relationship under concurrent or bypassed application writes.

## Rejected Alternatives

### Store the result on the workflow attempt

The attempt is still active during cleanup, and replacement ownership must not rewrite the original producer's terminal result or blur attempt lifecycle semantics.

### Extend the mutable publication intent

Publication reconciliation describes the external Git effect. Combining it with a child execution result would couple independently immutable evidence and orchestration lifecycles.

### Recreate the result after interruption

Rerunning the child or push could produce different output or repeat an external effect. Recovery must consume the already committed immutable handoff instead.

### Release first and persist later

An interruption in that gap could discard the only exact manifest after removing its worktree context. Requiring the result at both application and database boundaries closes that gap.
