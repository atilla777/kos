---
title: Recoverable Workflow Attempts
status: accepted
date: 2026-09-08
---

# ADR-0002: Recoverable Workflow Attempts

## Context

Agents and CLI connections can disappear while a workflow step owns work or after an external effect has occurred. Optimistic locking prevents lost database updates, but it cannot establish temporary ownership of an external side effect or determine whether an interrupted effect completed.

## Decision

Each workflow-status execution is a durable attempt. Before mutating KOS state or a repository, an orchestrator claims a bounded lease and monotonic fencing token for the task, status, and expected lock version. Stale tokens cannot complete a step. An expired attempt is reconciled before another attempt begins.

Every mutation follows the idempotency contract in the [architecture rules](../rules/architecture.md). External effects use persisted intent and observed-state reconciliation rather than blind repetition.

The observable contract is defined in [Workflow Execution](../specs/workflow-execution.md).

## Consequences

- Attempt failure or process loss need not advance workflow status or duplicate an effect.
- Lease and fencing checks are required in addition to optimistic locking.
- Side effects need operation-specific preconditions where an external system cannot enforce a fencing token.
- Recovery paths and ambiguous outcomes require fault-injection and concurrency tests.

## Rejected Alternatives

### Optimistic locking alone

It protects database writes but does not prevent a stale owner from performing an external side effect.

### Retry every interrupted operation

Blind retry can duplicate publication or overwrite the actual outcome of an operation that succeeded before its response was lost.

### Permanent attempt ownership

Ownership without expiry prevents recovery after an agent disappears.
