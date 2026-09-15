---
title: Durable Publication Preflight
task: BOOT-046
created: 2026-09-15
status: completed
---

# BOOT-046: Durable Publication Preflight

## Goal

Obtain a publication's expected remote OID only from a durable, verified observation of the configured trusted remote and base ref before creating the publication intent.

## User Outcome

A publication attempt can prepare its exact reviewed candidate and freeze publication context without direct Git access, guessed state, or a caller-supplied remote OID. Interrupted observation remains recoverable without a blind retry.

## Context

The released version 1 `publication.prepare` command accepts `expected_remote_oid` before publication context exists, while the authorized generic fetch path requires that context. Version 1 is immutable. The existing push adapter still performs its own immediate preflight and detects movement after preparation.

## Requirements

- BOOT-046-REQ-001: Preserve every released version 1 schema, endpoint, command, and behavior unchanged.
- BOOT-046-REQ-002: Add a minimal additive version 2 machine contract for durable publication preflight and preparation from its observation.
- BOOT-046-REQ-003: Persist a preflight intent before remote observation and bind it to the repository, task, current candidate generation, approved independent review, trusted remote and base ref, active publication attempt, lease, and fencing token.
- BOOT-046-REQ-004: Only `kos-repository` may observe the remote. It must revalidate repository trust and configuration, fetch the exact base ref with bounded output, and return closed evidence containing the observed OID, observation time, and canonical digest.
- BOOT-046-REQ-005: Reconciliation must verify canonical adapter evidence server-side before recording a concrete observation. An unknown or lost result remains unresolved and must be adopted and reconciled without blind retry.
- BOOT-046-REQ-006: Observed preparation must accept a reconciled preflight identifier instead of an OID, revalidate the current candidate, review, ownership, and target, and create the existing publication resource with the observed OID.
- BOOT-046-REQ-007: Concurrent prepare, reconcile, and consume operations must produce at most one active result while preserving established idempotency, optimistic-lock, lease, and fencing semantics.
- BOOT-046-REQ-008: Canonical runtime guidance must use only the authoritative preflight path for new publication attempts.

## Scope

- Durable publication-preflight persistence, constraints, ownership adoption, and recovery.
- Minimal version 2 CLI/API schemas and operations required by the preflight flow.
- A trusted remote observation adapter operation and shared canonical evidence verification.
- Observed publication preparation and publication-context integration.
- Canonical runtime guidance and installation integrity updates.
- Specifications, an architecture decision, and focused service, request, CLI, concurrency, contract, and real-Git tests.

## Non-Goals

- Push execution or `publication.complete`.
- Base-movement workflow recovery.
- Durable pending publication results.
- Worktree cleanup or terminal task completion.
- Modification of immutable `quick-fix@1.0.1` or any version 1 schema.
- A complete version 2 replacement for unrelated version 1 commands.

## Related Specifications And ADRs

- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Publication](../../docs/specs/publication.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [ADR-0001](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-046-DEC-001: Introduce a minimal additive version 2 surface rather than changing released version 1 semantics.
- BOOT-046-DEC-002: Keep the existing publication resource as the consumed result; a separate preflight resource represents the recoverable remote observation.
- BOOT-046-DEC-003: Keep the push adapter's immediate remote observation mandatory because a base ref may move after preflight.
- BOOT-046-DEC-004: Later publication completion will treat current candidate-bound passed test artifacts as mandatory check evidence.

## Acceptance Criteria

- BOOT-046-AC-001: A current publication attempt can durably observe the trusted base and prepare a publication whose expected OID cannot be supplied by the caller.
- BOOT-046-AC-002: Repository, target, candidate, attempt, fencing, evidence, timestamp, or observation mismatch is rejected without partial state.
- BOOT-046-AC-003: A crash or lost result permits adoption and reconciliation of the same preflight intent without an unobserved repeat.
- BOOT-046-AC-004: Concurrent mutations create and consume at most one active matching preflight and publication.
- BOOT-046-AC-005: Movement after preflight remains detectable by the existing push preflight.
- BOOT-046-AC-006: Version 1 contract fixtures remain byte- and behavior-compatible.
- BOOT-046-AC-007: Focused checks, `mise run check`, `git diff --check`, and independent review pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-046 active externally.
2. Add an ADR for minimal version 2 coexistence and update affected behavioral specifications.
3. Add publication-preflight persistence, constraints, services, adoption, and recovery.
4. Add closed version 2 CLI/API contracts and observed publication preparation.
5. Add the trusted remote observation adapter operation and canonical evidence verifier.
6. Update canonical runtime instructions and installation integrity data.
7. Add focused service, request, CLI, schema, concurrency, and real-Git coverage.
8. Run focused and full verification, validate the diff, and obtain independent review.
9. Record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused preflight service, request, CLI, adapter, contract, concurrency, and real-Git specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Completed verification on 2026-09-15:

- Focused version 2 CLI/API, persistence, migration, process-concurrency, runtime-installation, adapter-contract, and real-Git suites passed.
- The real-Git vertical flow passed from durable preflight preparation through adapter observation, server-verified reconciliation, observed publication preparation, and frozen version 1 publication context.
- Final `mise run check` passed with 795 examples and no failures, 217 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent review found and prompted fixes for executable capability verification, the version 2 `attempt_not_found` contract, unknown-result guidance, recovered reconciled-preflight ownership, and missing vertical and process-race coverage. Final re-review found no remaining correctness, security, reliability, compatibility, or test findings.

## Implementation Result

- Added a durable `PublicationPreflight` lifecycle with database-enforced identity, ownership, observation, consumption, uniqueness, and terminal immutability invariants.
- Added the minimal additive version 2 CLI/API contract for preflight read, prepare, reconcile, and observed publication preparation while leaving released version 1 schemas and endpoints unchanged.
- Added a version 2 `kos-repository publication_preflight` operation that validates registered trust under the repository lock, observes only the exact base ref, preserves refs and shared `FETCH_HEAD`, and returns canonical evidence verified again by Rails.
- Active preflights survive attempt expiry and are adopted in `prepared`, `unknown`, or `reconciled` state; observed preparation atomically consumes one reconciled preflight and copies its OID into the existing publication resource.
- Canonical runtime guidance now uses the authoritative preflight path, and installation readiness rejects CLI/API or repository executables that cannot execute and validate that contract.

## Risks

- A second protocol version adds compatibility burden; its initial surface is deliberately limited to commands that cannot be added safely to version 1.
- The remote may move after observation, so publication push must retain its independent immediate preflight.
- Local fixtures do not fully verify live HTTPS or SSH authentication behavior.
- The additive version 2 catalog is intentionally partial, so runtime clients use version 1 for all unrelated commands.
- Migration rollback necessarily removes version 2 preflight records; upgrade, empty rollback, and reapply are covered.
