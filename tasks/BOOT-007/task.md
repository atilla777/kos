---
title: Versioned CLI Protocol Contract
task: BOOT-007
created: 2026-09-09
---

# BOOT-007: Versioned CLI Protocol Contract

## Goal

Define the versioned JSON schemas, CLI commands, API bindings, and stable errors needed to implement the quick-fix workflow without implicit transport decisions. Simplify the development approval rule so one explicit approval of the final baseline also authorizes implementation and publication.

## User Outcome

KOS contributors can implement the first CLI and API against one testable machine contract. A user approves each task once after reviewing its final requirements and plan instead of answering a second authorization prompt.

## Context

The Rails application currently exposes only its health endpoint. Existing specifications require a versioned REST API, a non-interactive Ruby CLI, idempotent mutations, optimistic locking, leases, fencing, artifact validation, and recoverable Git protocols, but leave exact wire schemas and errors to this task. The collaboration rules currently require separate baseline approval and implementation authorization even though approval is intended to authorize the described work.

## Requirements

- BOOT-007-REQ-001: Define the complete operational-MVP CLI command surface and bind every command to a versioned API request and response.
- BOOT-007-REQ-002: Define strict, versioned JSON schemas for protocol envelopes, commands, workflow context and results, resources, and artifact evidence.
- BOOT-007-REQ-003: Define stable error categories and leaf codes with HTTP statuses, CLI exit statuses, retry behavior, and safe structured details.
- BOOT-007-REQ-004: Define command-specific repository scope, idempotency, optimistic-lock, lease, and fencing requirements.
- BOOT-007-REQ-005: Preserve atomic artifact registration and workflow transition on successful step completion and explicit recovery protocols around external effects.
- BOOT-007-REQ-006: Cover every public schema with automated contract validation and representative valid and invalid cases.
- BOOT-007-REQ-007: Make explicit approval of the final requirements and implementation plan authorize implementation, verification, commit, and normal push; ambiguous approval remains insufficient.

## Scope

- Add a focused normative CLI protocol specification and index it.
- Add a versioned JSON Schema tree, command and error catalogs, and representative fixtures.
- Add contract tests and the minimum schema-validation dependency.
- Update adjacent specifications only to link to the authoritative protocol contract or resolve an existing wording conflict.
- Update the collaboration rule and the matching repository agent instruction to use one approval decision.
- Update the external bootstrap plan, then commit and publish the verified task.

## Non-Goals

- Implementing Rails API endpoints, authentication, persistence, the Ruby CLI, or Git adapters.
- Defining the `.kos` YAML schema or canonical workflow bundle digest assigned to BOOT-008.
- Defining central state layout, migration policy, or repository registration UX assigned to BOOT-009.
- Adding deferred feature, initiative, hierarchy, second-runtime, or retrospective commands.

## Related Specifications And ADRs

- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Publication](../../docs/specs/publication.md)
- [ADR-0001: Central REST API and Multi-Repository State](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-007-DEC-001: Contract only the quick-fix operational MVP while defining versioning rules for later compatible extensions.
- BOOT-007-DEC-002: Use JSON Schema draft 2020-12, versioned identifiers and document fields, local references, snake-case properties, omitted optional values, and closed object shapes.
- BOOT-007-DEC-003: Carry repository identity in API paths and mutation preconditions in JSON bodies; carry authentication and idempotency in standard request headers.
- BOOT-007-DEC-004: Use stable error categories plus specific leaf codes; only transient errors are automatically retryable.
- BOOT-007-DEC-005: Require fencing only for active-attempt and external-effect mutations. Task creation requires idempotency but no fencing token.
- BOOT-007-DEC-006: Let successful step completion register transition artifacts atomically. Standalone registration cannot satisfy a workflow transition.
- BOOT-007-DEC-007: Model publication as explicit prepare, observed-state reconciliation, and completion operations around Git effects owned by `kos-repository`.
- BOOT-007-DEC-008: Treat one explicit approval of the final task baseline as authorization for the full implementation and publication lifecycle.

## Acceptance Criteria

- BOOT-007-AC-001: Every operational-MVP command has exact CLI syntax, HTTP method and path, request and response schemas, preconditions, HTTP statuses, and CLI exit statuses.
- BOOT-007-AC-002: Every JSON schema validates against its metaschema, has a unique versioned identifier, and resolves references without network access.
- BOOT-007-AC-003: Representative valid fixtures pass and invalid fixtures fail for protocol envelopes, mutations, step completion, artifact generations, and recovery evidence.
- BOOT-007-AC-004: The command matrix explicitly and consistently assigns repository scope, idempotency, expected lock version, lease, and fencing requirements.
- BOOT-007-AC-005: The error catalog covers authentication, authorization, malformed input, unsupported versions, stale state, lost leases, idempotency conflicts, invalid transitions and artifacts, base movement, transient transport failures, and internal failures.
- BOOT-007-AC-006: The collaboration rules require one explicit baseline approval and do not require a separate implementation authorization.
- BOOT-007-AC-007: All required project checks pass and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved task baseline and mark BOOT-007 active externally.
2. Define the normative protocol, command matrix, versioning policy, preconditions, idempotency behavior, and error catalog.
3. Add versioned schemas for common envelopes, resources, commands, workflow step transport, artifacts, and recoverable external-effect evidence.
4. Add representative fixtures and contract tests that validate schemas, local references, command coverage, and stable errors.
5. Update adjacent specifications and change the approval rule without broadening other collaboration behavior.
6. Run schema, test, lint, security, autoloading, and diff checks and resolve failures within scope.
7. Update the external plan, commit the task files, and push normally to the default branch.

## Verification

- Run focused schema contract specs while iterating.
- Run `bundle exec rspec`.
- Run `bundle exec rubocop`.
- Run `bin/rails zeitwerk:check`.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Verification Results

- `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb`: 119 examples, 0 failures.
- `mise run check`: 120 examples, 0 failures; 21 RuboCop files without offenses; Brakeman reported no warnings; bundler-audit reported no vulnerabilities; Zeitwerk check passed.
- `git diff --check`: passed.
- Independent contract review found no remaining high-severity issue; the final publication-lifecycle finding was covered by schema and contract test.

## Risks

- BOOT-007-RISK-001: Later `.kos` and repository-registration contracts may need additive v1 fields. Keep optional extension points explicit and require a major version for incompatible wire changes.
- BOOT-007-RISK-002: A broad command surface could pre-implement deferred behavior. Limit commands and schemas to the quick-fix workflow and its required recovery paths.
- BOOT-007-RISK-003: Client-supplied Git evidence could be treated as trusted assertion. Require structured observations tied to the prepared operation and leave Git verification ownership with `kos-repository`.
