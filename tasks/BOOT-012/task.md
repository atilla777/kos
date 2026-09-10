---
title: Versioned Read-Only REST API And CLI
task: BOOT-012
created: 2026-09-10
---

# BOOT-012: Versioned Read-Only REST API And CLI

## Goal

Provide the first agent-facing read access to KOS state through the Ruby CLI and authenticated Rails REST API version 1.

## User Outcome

Agents can use non-interactive `kos ... --json` commands to inspect the shared workflow catalog and repository-scoped task execution state through schema-validated JSON.

## Context

BOOT-010 and BOOT-011 persist the workflow catalog, tasks, attempts, artifacts, and worktree reservations. Their state is not yet available through the required REST and CLI boundary. The version 1 schemas and command catalog already define the external wire contract.

## Requirements

- BOOT-012-REQ-001: Implement `task-type list`, `workflow list`, `workflow get`, and `workflow-draft get` as authenticated global reads.
- BOOT-012-REQ-002: Implement `task get`, `attempt get`, `worktree get`, and `artifact list` as authenticated repository-scoped reads.
- BOOT-012-REQ-003: Resolve repository scope from its immutable UUID and return the same `repository_access_denied` failure for absent and inaccessible repositories.
- BOOT-012-REQ-004: Return version 1 success and failure envelopes with UUID request IDs, stable error categories and codes, schema-valid resources, and RFC 3339 UTC timestamps.
- BOOT-012-REQ-005: Require a bearer token from `KOS_API_TOKEN` for every implemented API endpoint while keeping `GET /up` public, and do not log or return the token.
- BOOT-012-REQ-006: Implement the Ruby CLI as the sole agent-facing state interface, taking its URL, bearer token, and timeout from the specified environment variables and reserving stdout for one JSON result.
- BOOT-012-REQ-007: Validate CLI arguments and API responses against the checked-in schemas, preserve stable CLI exit statuses, and retry reads at most three times only for transport or transient failures.
- BOOT-012-REQ-008: Provide deterministic bounded pagination with opaque cursors bound to the command and repository or task filters.
- BOOT-012-REQ-009: List only published workflow versions and reconstruct a complete deterministic workflow definition for `workflow get` from normalized immutable rows.
- BOOT-012-REQ-010: Derive task status from its terminal workflow state and active attempt state rather than adding independently mutable state.
- BOOT-012-REQ-011: Permit a task type without an activated workflow by omitting `current_workflow_version_id` until activation, correcting the unreleased version 1 resource schema to match the persistence contract.

## Scope

- Versioned API routes, authentication, repository scoping, pagination, response envelopes, serializers, and read controllers.
- Ruby CLI parsing, schema validation, HTTP transport, retries, JSON output, and stable exits for the eight approved commands.
- Contract, request, and CLI integration tests.
- The pre-release task-type schema correction and user-facing CLI documentation.

## Non-Goals

- Mutating endpoints, idempotency execution, and repository registration.
- Runtime configuration reads or updates.
- Workflow validation, import, publication, activation, or export, which remain BOOT-019.
- Task creation, which remains BOOT-013.
- Repository-effect and publication reads because their persistence is not implemented.
- Multi-worker Puma integration testing.

## Related Specifications And ADRs

- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [Workflow Catalog](../../docs/specs/workflow-catalog.md)
- [Task Model](../../docs/specs/task-model.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [ADR-0001: Central REST API](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0005: Central Persistence And Registration](../../docs/decisions/0005-central-persistence-and-registration.md)
- [ADR-0007: Central Workflow Catalog](../../docs/decisions/0007-central-workflow-catalog.md)

## Task-Local Decisions

- BOOT-012-DEC-001: Omit `current_workflow_version_id` from a task-type resource before first activation. This aligns the unreleased schema with the accepted persistence contract without publishing a workflow early.
- BOOT-012-DEC-002: Implement only reads backed by current persistence. Later tasks add runtime config, repository effects, publications, and catalog mutations without placeholder resources.
- BOOT-012-DEC-003: Encode cursor position together with command and scope so a cursor cannot be reused for a different list operation.

## Acceptance Criteria

- BOOT-012-AC-001: All eight approved API endpoints and CLI commands return schema-valid version 1 success documents.
- BOOT-012-AC-002: Authentication, malformed input, unsupported version, resource absence, and repository isolation return schema-valid failures with specified HTTP and CLI statuses.
- BOOT-012-AC-003: Pagination is deterministic, bounded to 100 records, and rejects a cursor from another command or scope.
- BOOT-012-AC-004: Workflow serialization returns the complete normalized definition in deterministic order, and catalog listing excludes unpublished versions.
- BOOT-012-AC-005: CLI transport tests cover environment configuration, headers, retries, one-document stdout, diagnostics, and stable exits.
- BOOT-012-AC-006: Required focused and full project checks pass, and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-012 active externally.
2. Correct the task-type schema and add shared schema, envelope, authentication, serialization, and pagination infrastructure.
3. Implement the four global and four repository-scoped REST reads.
4. Implement the Ruby CLI parser, HTTP transport, validation, retry policy, and executable.
5. Add contract, request, and CLI integration tests for success and failure behavior.
6. Run focused specs, the full project checks, and diff validation.
7. Independently review the implementation and resolve findings within scope.
8. Record verification and results, update the external plan, commit, and push normally.

## Verification

- Run focused request, CLI, and contract specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Verification completed on 2026-09-10:

- `bundle exec rspec spec/requests/api/v1/reads_spec.rb spec/integration/kos/cli/application_spec.rb spec/contracts/cli_v1_contract_spec.rb spec/models/workflow_attempt_spec.rb`: 152 examples, 0 failures.
- Final focused request and CLI regression suite: 31 examples, 0 failures.
- `mise run check`: passed with 238 examples, 0 failures, 74 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check`: passed.
- Independent review found no remaining high- or medium-severity findings after transport-error, cursor precision and size, task-status ordering, terminal-status, and locator-validation corrections.

## Implementation Result

- Added bearer-authenticated Rails API version 1 reads for task types, published workflow versions, workflow drafts, tasks, attempts, worktree reservations, and task artifacts.
- Added schema-validated success and failure envelopes, repository isolation, deterministic keyset pagination, and HMAC-bound opaque cursors.
- Added deterministic reconstruction of complete published workflow definitions from normalized immutable records.
- Added the `bin/kos` Ruby CLI with schema-based argument and response validation, environment-based transport configuration, bounded read retries, stable exits, and one-document JSON output.
- Corrected the unreleased task-type resource schema so an inactive task type omits `current_workflow_version_id` before first workflow activation.
- Added request, CLI transport, model, and contract coverage for authentication, malformed input, unsupported versions, repository isolation, resource absence, cursor boundaries, retry exhaustion, and derived task status.

## Risks

- BOOT-012-RISK-001: Reconstructing the canonical workflow definition from normalized records can produce ordering or omission defects unless contract-tested with a complete graph.
- BOOT-012-RISK-002: Rack request tests and controlled CLI transport tests do not exercise a multi-worker Puma process.
- BOOT-012-RISK-003: Error handling must avoid converting programmer errors or secret-bearing transport details into unsafe machine responses.
