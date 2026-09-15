---
title: Minimal CLI Version 2 Coexistence
status: accepted
date: 2026-09-15
bootstrap_task: BOOT-046
---

# ADR-0011: Minimal CLI Version 2 Coexistence

## Context

The released CLI and API version 1 contract allows `publication.prepare` to accept a caller-supplied expected remote OID. A trustworthy publication preflight must instead persist intent before Git observation and derive that OID from verified adapter evidence. Changing the version 1 command would alter a released request shape and meaning.

A complete copy of every version 1 command into a new namespace would add substantial implementation and compatibility work unrelated to publication preflight. KOS needs a way to evolve one unsafe boundary while continuing to serve existing version 1 clients unchanged.

## Decision

KOS introduces a minimal additive CLI and API version 2 contract containing only `publication_preflight.get`, `publication_preflight.prepare`, `publication_preflight.reconcile`, and `publication.prepare_observed`. Their API endpoints are repository-scoped under `/api/v2/repositories/{repository_id}`. All version 2 documents identify `"schema_version": "2"` and are closed JSON Schema draft 2020-12 documents.

Version 1 remains immutable and may coexist with version 2. A protocol major version identifies a document and command surface, not a requirement to duplicate every command from earlier versions. Clients use version 1 for commands not present in the deliberately partial version 2 catalog.

The version 2 preflight resource is the durable observation intent. It binds the task, reviewed candidate, trusted remote, full base ref, preparing attempt, current owning attempt, and lease-fenced mutation preconditions. It moves through `prepared`, `unknown`, `reconciled`, and `consumed`. Concrete reconciliation records only server-verified canonical adapter evidence. An unknown result remains unresolved and recoverable; it never authorizes observed publication preparation or blind repetition.

`publication.prepare_observed` consumes one reconciled preflight and creates the existing publication-shaped resource. Its `expected_remote_oid` is copied from the preflight's verified `observed_remote_oid`; the caller supplies only the preflight identifier and leased preconditions. The push adapter retains its independent immediate remote observation because the ref may move after preflight.

## Consequences

- Released version 1 schemas, endpoints, commands, and meanings do not change.
- Servers and clients can implement the four version 2 commands without porting unrelated version 1 operations.
- A version 2 client may also use version 1; each individual request and response remains wholly within one schema version.
- Preflight observation is durable, lease-owned, idempotent, adoptable after interruption, and consumed at most once.
- Publication preparation can no longer trust a caller-supplied remote OID on the version 2 path.
- Version 2 carries a small additional catalog and schema set that must remain compatible once released.

## Rejected Alternatives

### Change version 1 publication preparation

Removing or changing `expected_remote_oid` would break the immutable released contract and existing consumers.

### Duplicate the complete version 1 surface in version 2

This would provide one uniform namespace but would broaden the task without improving the safety of the publication boundary.

### Observe the remote without durable preflight state

An interruption would leave no authoritative intent or observation to adopt and reconcile, encouraging an unsafe blind retry.

### Let observed publication preparation accept an OID

That would preserve the trust gap under a new command name and would not prove that the value came from canonical adapter evidence.
