---
title: Workflow Catalog Administration
task: BOOT-019
created: 2026-09-11
---

# BOOT-019: Workflow Catalog Administration

## Goal

Implement the complete global workflow-catalog write path for draft import, validation, atomic publication, activation, and canonical export.

## User Outcome

An agent can use `bin/kos` to import a complete workflow draft, inspect deterministic validation errors, publish an immutable version, activate it for new tasks, and export the canonical definition used for its content digest.

## Context

The persistence models, database constraints, read-only REST API and CLI, and draft protocol version 1 contracts already exist. Domain operations, whole-graph validation, canonical digest generation, global idempotency execution, the five catalog endpoints, and their CLI commands are not implemented.

## Requirements

- BOOT-019-REQ-001: Implement `workflow-draft import`, `workflow-draft validate`, `workflow publish`, `workflow activate`, and `workflow export` according to the existing version 1 schemas and HTTP bindings.
- BOOT-019-REQ-002: Let the first import create a missing draft only with `expected_lock_version` zero; make later imports replace the complete document under optimistic locking.
- BOOT-019-REQ-003: Reject malformed, schema-invalid, or identity-invalid imports while allowing a schema-valid draft with graph errors to be stored and inspected before publication.
- BOOT-019-REQ-004: Return deterministic whole-graph validation errors without changing catalog state.
- BOOT-019-REQ-005: Validate and create the complete normalized immutable workflow version in one database transaction without exposing partial publication state.
- BOOT-019-REQ-006: Return the existing immutable version with HTTP 201 when a new idempotency key republishes the same semantic version and canonical content; reject different content under that version as `workflow_version_conflict`.
- BOOT-019-REQ-007: Normalize every semantically unordered workflow-definition array, including conjunctive conditions, and compute the content digest with a complete RFC 8785 JSON Canonicalization Scheme implementation.
- BOOT-019-REQ-008: Activate only a published version belonging to the task type under optimistic locking, without changing existing tasks' pinned workflow versions.
- BOOT-019-REQ-009: Execute catalog mutations with global idempotency scope, canonical request fingerprints, original status and result replay, and conflict detection. Record transaction-only completed operations atomically without an artificial external-effect intent.
- BOOT-019-REQ-010: Preserve schema-valid response envelopes and stable errors and extend the CLI with input-file or stdin mutations, POST transport, headers, and bounded retries that reuse the original idempotency key.

## Scope

- Domain and application objects for validation, canonical definitions, import, publication, activation, and global idempotency.
- REST routes, controllers, serializers, and CLI transport and parsing for the five catalog operations.
- A focused internal RFC 8785 canonicalizer verified against official vectors.
- Unit, persistence, request, CLI integration, and contract tests.
- User documentation and external development-plan updates.

## Non-Goals

- Task creation, runtime configuration, repository registration, or workflow-execution mutations.
- Partial editing of draft members, repository-specific workflow assignments, or active-task workflow migration.
- A new protocol version or separate draft-creation command.
- Updating or deleting published workflow content.

## Related Specifications And ADRs

- [Workflow Catalog](../../docs/specs/workflow-catalog.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0001: Central REST API](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0007: Central Workflow Catalog](../../docs/decisions/0007-central-workflow-catalog.md)

## Task-Local Decisions

- BOOT-019-DEC-001: An absent draft is created by import when its expected lock version is zero; this avoids adding an otherwise unnecessary creation command.
- BOOT-019-DEC-002: Import validates shape and identity but permits graph-invalid authoring state. Validation reports those errors and publication rejects them.
- BOOT-019-DEC-003: Republishing identical canonical content under the same semantic version returns the existing version and the cataloged HTTP 201 status.
- BOOT-019-DEC-004: Semantically unordered definition arrays are normalized before export and digest generation, so representational reordering does not create different content. The initially selected canonicalization gem was rejected after review exposed numeric precision loss; a focused internal RFC 8785 implementation is verified against official vectors instead.
- BOOT-019-DEC-005: Catalog mutations without external effects write only a completed idempotency record in the same transaction as their state change.

## Acceptance Criteria

- BOOT-019-AC-001: All five API endpoints and CLI commands return schema-valid protocol version 1 documents with their cataloged HTTP and CLI statuses.
- BOOT-019-AC-002: Validation covers graph, artifact, repository-policy, UTF-8, and content-size invariants with deterministic errors.
- BOOT-019-AC-003: Draft creation and replacement, stale locks, identity mismatches, idempotency replay and conflict, and concurrent calls are covered.
- BOOT-019-AC-004: Publication rollback leaves no version or child rows, and all published content remains immutable.
- BOOT-019-AC-005: Export is deterministic and matches the stored digest; reordering semantically unordered arrays does not change it.
- BOOT-019-AC-006: Activation affects only tasks created after it and does not change existing task workflow-version references.
- BOOT-019-AC-007: Focused checks, the full project check, diff validation, and independent review pass before the task is committed and pushed to `main`.

## Implementation Plan

1. Record this baseline and mark BOOT-019 active externally.
2. Add RFC 8785 canonicalization and the whole-definition validator with focused unit tests.
3. Implement canonical export, draft import, atomic publication, activation, and transactional global idempotency.
4. Add REST routes and actions with request validation, cataloged statuses, and safe error mapping.
5. Extend the CLI for mutation input, POST transport, idempotency headers, and bounded retries.
6. Add persistence, request, CLI, and contract coverage, including concurrency and publication rollback.
7. Update user documentation and run focused checks, the full project check, diff validation, and independent review.
8. Complete the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused workflow-catalog domain, request, CLI, contract, and persistence specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-11:

- Focused workflow-catalog, idempotency, request, CLI, contract, and concurrency suites passed throughout implementation.
- `mise run check`: passed with 300 examples, 0 failures, 91 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found no remaining findings after RFC 8785 numeric, duplicate-member parsing, non-object mutation input, SQLite retry, and deterministic transaction-overlap corrections.

## Implementation Result

- Added deterministic whole-definition validation, semantic normalization, RFC 8785 canonical JSON, and content digests.
- Added transactional draft import and replacement, immutable publication, activation, canonical export, and global idempotency with bounded SQLite contention handling.
- Added five versioned REST/CLI operations with schema validation, stable failures, input files or stdin, idempotency headers, and bounded retry behavior.
- Added domain, persistence, request, CLI, contract, rollback, replay, and synchronized subprocess concurrency coverage.
- Documented the workflow-catalog administration commands in the user README.

## Risks

- BOOT-019-RISK-001: RFC 8785 has subtle numeric and UTF-16 ordering rules; official conformance vectors protect the internal implementation.
- BOOT-019-RISK-002: SQLite concurrency may expose races that model-level optimistic locking alone does not cover; competing transactions require integration coverage.
- BOOT-019-RISK-003: The validator has many independent normative rules; each rule requires an explicit focused example to avoid silent omissions.
