---
title: Workflow Attempt Ownership Lifecycle
task: BOOT-021
created: 2026-09-11
---

# BOOT-021: Workflow Attempt Ownership Lifecycle

## Goal

Implement the version 1 workflow-attempt ownership lifecycle with atomic claim, bounded lease renewal, controlled interruption, durable reconciliation, and stale-owner protection.

## User Outcome

An orchestrator can claim the current executable task step, retain ownership while working, report failure or a human decision safely, and recover an expired attempt before another orchestrator continues. Two orchestrators cannot own or finish the same attempt concurrently.

## Context

Workflow-attempt persistence, database invariants, read serialization, command schemas, repository-scoped idempotency, and `attempt.get` already exist. The five lifecycle mutations are declared by the draft version 1 protocol but are not connected to application operations, the Rails API, or the Ruby CLI.

## Requirements

- BOOT-021-REQ-001: `attempt.claim` atomically locks the repository task, checks its expected lock version and executable current workflow state, rejects any unreconciled started attempt, and creates the next monotonic fencing token with a bounded lease.
- BOOT-021-REQ-002: A live or expired-but-unreconciled started attempt blocks claim with `invalid_transition`; a new claim is allowed only after the prior attempt has reached a terminal state.
- BOOT-021-REQ-003: The active attempt ID and current fencing token establish ownership for leased mutations without adding owner identity to leased preconditions.
- BOOT-021-REQ-004: `attempt.renew` checks task lock version, active ownership, fencing token, and lease expiry, then sets heartbeat to the current time and expiry to that time plus the requested duration.
- BOOT-021-REQ-005: A lease whose expiry is less than or equal to the current time is expired. Fencing-token validation precedes expiry validation when both would fail.
- BOOT-021-REQ-006: `attempt.fail` and `attempt.needs_human` require frozen context and an exactly bound result manifest, release active ownership and lease atomically, and do not advance workflow status.
- BOOT-021-REQ-007: Failed and needs-human artifact entries remain durable inside the immutable result manifest but are not registered as `TaskArtifact` rows.
- BOOT-021-REQ-008: `attempt.reconcile` requires an expired started or already interrupted attempt, requires no fencing token, records immutable observation state, evidence digest, and observation time, and never asserts that an external effect succeeded.
- BOOT-021-REQ-009: Reconciliation changes an expired attempt to interrupted and clears active ownership and lease atomically. Repeating it for an interrupted attempt with the same evidence returns the attempt; different evidence returns `invalid_transition`.
- BOOT-021-REQ-010: All five mutations use repository-scoped idempotency, with completed replay preceding mutable lock, lease, and fencing checks.
- BOOT-021-REQ-011: API paths and command bodies must identify the same task or attempt. Cross-repository or missing attempts return `attempt_not_found` without disclosure.
- BOOT-021-REQ-012: Missing or mismatched frozen context returns `context_unavailable`; expired leases and stale tokens retain their version 1 `lease_lost` errors.
- BOOT-021-REQ-013: A serialized started attempt requires heartbeat and lease-expiry fields, matching the normative contract and persistence invariants.

## Scope

- Workflow-attempt lifecycle application operations and persistence constraints.
- Durable reconciliation observation fields and migration.
- Authenticated REST routes and thin controller actions for the five mutations.
- Ruby CLI parsing and transport bindings for the existing version 1 commands.
- Draft version 1 schemas and normative specification clarifications required by the approved decisions.
- Service, request, CLI, contract, persistence, and multi-process concurrency tests.

## Non-Goals

- Step-context finalization, successful step completion, transition artifact registration, or workflow-state advancement.
- Worktree, repository-effect, or publication mutation and adoption behavior.
- Git side effects, authenticated actor identity, new CLI aliases, or new stable error codes.
- Substantive review of result-manifest or artifact content.

## Related Specifications And ADRs

- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [Task Model](../../docs/specs/task-model.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)

## Task-Local Decisions

- BOOT-021-DEC-001: The current attempt ID and fencing token are the leased-operation authority; `owner_id` remains claim metadata rather than a repeated mutation precondition.
- BOOT-021-DEC-002: Renewal creates a fresh bounded lease from its heartbeat time rather than accumulating duration from the old expiry.
- BOOT-021-DEC-003: Fencing mismatch is checked before expiry, and equality with the expiry time means the lease is lost.
- BOOT-021-DEC-004: Attempt reconciliation evidence is immutable durable classification. It interrupts ownership but does not prove or complete any worktree, repository, or publication effect.
- BOOT-021-DEC-005: Failed and needs-human manifest artifacts are retained only in the terminal manifest because these operations do not perform a workflow transition.
- BOOT-021-DEC-006: Roadmap names such as `claim-step` are outcome descriptions; only the normative `kos attempt ...` commands are implemented.

## Acceptance Criteria

- BOOT-021-AC-001: Simultaneous claim requests create exactly one started attempt and the other returns a controlled conflict.
- BOOT-021-AC-002: Each later attempt receives the next non-reused fencing token only after prior ownership is terminal.
- BOOT-021-AC-003: Renew succeeds only for the active owner before expiry and updates heartbeat and bounded expiry deterministically.
- BOOT-021-AC-004: Fail and needs-human atomically terminalize ownership, leave workflow state unchanged, and derive task status as open and blocked respectively.
- BOOT-021-AC-005: An expired attempt blocks claim until reconciliation; reconciliation persists immutable evidence and permits a later claim.
- BOOT-021-AC-006: A stale owner cannot mutate state after reconciliation and replacement and receives `fencing_token_stale` when its token is invalid.
- BOOT-021-AC-007: Completed idempotency replay returns the original semantic response after lease expiry without repeating state changes.
- BOOT-021-AC-008: API and CLI documents satisfy draft version 1 schemas and stable HTTP and CLI error mappings.
- BOOT-021-AC-009: Focused checks, the full project check, and diff validation pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-021 active externally.
2. Add reconciliation persistence fields and database constraints.
3. Implement atomic claim, renew, terminal interruption, and reconciliation operations with a consistent lock, fencing, and lease-check order.
4. Add Rails routes, controller actions, idempotency execution, path/body validation, and operation-error category mapping.
5. Add the five Ruby CLI command and path bindings, including nested leased-precondition path values.
6. Tighten the draft attempt resource and clarify the normative version 1 lifecycle behavior.
7. Add service, request, CLI, contract, persistence, idempotency, and synchronized multi-process concurrency coverage.
8. Run focused checks, the full project quality gate, RuboCop, and diff validation.
9. Record verification and implementation results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused workflow-attempt service, request, CLI, contract, model, idempotency, and concurrency specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused lifecycle service, API request, CLI transport, protocol contract, persistence, synchronized process-claim, and populated migration/rollback suites passed throughout implementation.
- `mise run check`: passed with 348 examples, 0 failures, 106 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found no remaining correctness findings after reconciliation migration compatibility, trigger preservation, terminal resource shape, stale-owner, and idempotency replay corrections.

## Implementation Result

- Added atomic claim, bounded lease renewal, controlled failed and needs-human completion, and expired-attempt reconciliation application operations.
- Added authenticated, repository-scoped REST and Ruby CLI bindings for all five version 1 attempt lifecycle mutations with idempotent replay and stable lease-loss errors.
- Added immutable reconciliation observation persistence while preserving pre-existing interrupted rows through a protected one-time migration marker.
- Tightened attempt resource lifecycle shapes and documented fencing, lease-expiry, manifest, and reconciliation behavior.
- Added service, request, CLI, contract, model, separate-process claim race, and populated migration/rollback coverage.
- Made the shared workflow catalog test helper deterministic on a clean test database.

## Risks

- BOOT-021-RISK-001: SQLite claim races can violate ownership despite passing in-process transactional tests; synchronized separate-process coverage is required.
- BOOT-021-RISK-002: Changing terminal-attempt constraints for immutable reconciliation fields must remain safe for existing rows and preserve terminal immutability.
- BOOT-021-RISK-003: Reconciliation classifications cannot yet validate future effect or publication resources; this task stores the evidence but deliberately does not interpret it as effect success.

The remaining risk is BOOT-021-RISK-003. Renew-versus-reconcile and finish-versus-reconcile were not separately synchronized across processes; their ownership changes use the same locked task transaction and the acceptance-critical simultaneous claim race is covered end to end.
