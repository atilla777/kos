---
title: Deterministic Workflow Step Context
task: BOOT-016
created: 2026-09-09
---

# BOOT-016: Deterministic Workflow Step Context

## Goal

Close the contract gap between a task's pinned workflow bundle and the exact context executed by an agent.

## User Outcome

An agent obtains one verified, self-contained context for its active workflow step through the KOS CLI and never needs direct access to KOS snapshot storage.

## Context

The current specifications require execution from an immutable pinned bundle, but the CLI protocol exposes neither instruction content nor a snapshot locator. The workflow context schema carries digests without defining how instruction bytes, referenced materials, and worktree context are assembled or when the input-context digest becomes final. CLI protocol version 1 has not been implemented or released and remains a draft contract that can be corrected before its release boundary is established.

## Requirements

- BOOT-016-REQ-001: Define one idempotent CLI/API mutation that atomically freezes and returns the complete executable context for an active workflow attempt.
- BOOT-016-REQ-002: Include the exact Markdown instruction and every referenced template or material needed by the step, with media types and content digests.
- BOOT-016-REQ-003: Derive instruction, materials, allowed capabilities, and artifact requirements from the task's pinned immutable bundle and current workflow status.
- BOOT-016-REQ-004: Bind the context to repository, task, attempt, workflow status, lease ownership, and the confirmed worktree when the status requires one.
- BOOT-016-REQ-005: Define canonical instruction, material, and input-context digest inputs and verify them before returning context.
- BOOT-016-REQ-006: Keep snapshot storage paths and layout outside the agent-facing contract.
- BOOT-016-REQ-007: Correct the unreleased draft CLI v1 schemas, fixtures, catalog, and versioning language to cover this operation.
- BOOT-016-REQ-008: Record future persistence portability as a separate planning outcome without implementing a replaceable backend, Beads, or Dolt integration.

## Scope

- Update workflow execution, project configuration, runtime integration, and CLI protocol specifications.
- Update draft CLI v1 JSON schemas, representative fixtures, and contract tests.
- Update the external bootstrap plan with the refined immediate work and a separate persistence-boundary follow-up.
- Commit and publish the verified documentation and contract correction.

## Non-Goals

- Implementing Rails API endpoints, the Ruby CLI, snapshot persistence, workflow loading, or runtime skills.
- Defining the detailed `.kos` YAML schema and canonical bundle digest assigned to BOOT-008.
- Implementing pluggable persistence, a Beads or Dolt adapter, or cross-backend migration.
- Guaranteeing that a future external backend can satisfy KOS transaction, idempotency, lease, fencing, and recovery semantics.

## Related Specifications And ADRs

- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Project Configuration](../../docs/specs/project-configuration.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [ADR-0003: Pinned Project Workflows](../../docs/decisions/0003-pinned-project-workflows.md)

## Task-Local Decisions

- BOOT-016-DEC-001: Return inline UTF-8 instruction and material content through KOS rather than exposing a snapshot path.
- BOOT-016-DEC-002: Use one attempt-bound `step.context` mutation instead of separate instruction and metadata reads. It atomically stores the complete context and digest, and idempotent repeats return the same context.
- BOOT-016-DEC-003: Finalize executable context only after any required worktree is confirmed; attempt claim therefore precedes context construction.
- BOOT-016-DEC-004: Treat the checked-in protocol v1 as an unreleased draft until its first implemented release, while preserving immutability after release.
- BOOT-016-DEC-005: Keep skills and workflow instructions independent of the selected persistence implementation; defer any concrete alternate backend.

## Acceptance Criteria

- BOOT-016-AC-001: The machine contract has an exact `step.context` CLI syntax, HTTP binding, request, result, and stable errors.
- BOOT-016-AC-002: A workflow context is self-contained and includes verified instruction and referenced material content without snapshot paths.
- BOOT-016-AC-003: The contract defines byte-level member digests and a canonical input-context digest.
- BOOT-016-AC-004: Context retrieval rejects an inactive attempt, mismatched status, unavailable required worktree, and corrupt pinned content.
- BOOT-016-AC-005: Contract tests cover the new command and representative valid and invalid contexts.
- BOOT-016-AC-006: The external plan keeps BOOT-008 next and records persistence-boundary portability separately from MVP implementation.
- BOOT-016-AC-007: All required project checks pass and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-016 active externally.
2. Define deterministic context assembly, content verification, and lifecycle behavior in the domain specifications.
3. Add `step.context` to the draft CLI v1 command and response schemas and catalog.
4. Add representative fixtures and contract coverage for complete context and command consistency.
5. Update the external roadmap and backlog while preserving BOOT-008 as the next task.
6. Run contract, test, lint, security, autoloading, and diff checks and resolve failures within scope.
7. Update the external plan, commit the task files, and push normally to the default branch.

## Verification

- Run `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb` while iterating.
- Run `bundle exec rspec`.
- Run `bundle exec rubocop`.
- Run `bin/rails zeitwerk:check`.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Verification Results

- `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb`: 133 examples, 0 failures.
- `mise run check`: 134 examples, 0 failures; 21 RuboCop files without offenses; Brakeman reported no warnings; bundler-audit reported no vulnerabilities; Zeitwerk check passed.
- `git diff --check`: passed.
- Independent contract review found no remaining issues after terminal-state, member-path, cross-field binding, byte-limit, idempotency-order, and canonical-digest findings were corrected.

## Risks

- BOOT-016-RISK-001: Inline materials can make responses large. Bound each member and the complete context explicitly.
- BOOT-016-RISK-002: Context assembled before worktree confirmation can become incomplete or non-replayable. Require confirmed worktree state before finalization when the step needs one.
- BOOT-016-RISK-003: Calling v1 mutable indefinitely would weaken compatibility. Limit draft correction to the period before the first implemented release and retain major-version rules afterward.
- BOOT-016-RISK-004: A future storage adapter may not provide KOS reliability semantics. Require conformance to domain operations rather than promising compatibility with a named backend.
