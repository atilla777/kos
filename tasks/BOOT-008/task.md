---
title: Project Workflow Schema And Canonical Bundle Digest
task: BOOT-008
created: 2026-09-09
---

# BOOT-008: Project Workflow Schema And Canonical Bundle Digest

## Goal

Define an executable and unambiguous version 1 contract for project-owned `.kos` task types, workflows, referenced members, and immutable workflow bundle identity.

## User Outcome

Projects can describe workflows in validated YAML, and every implementation of KOS can assemble the same bundle manifest and SHA-256 digest from the same exact files.

## Context

The current specifications establish project ownership, an illustrative `.kos` layout, immutable pinned snapshots, typed workflow conditions, and exact member digests. They do not define the detailed YAML shape, graph and reference validation, or the canonical input for the aggregate bundle digest. The unreleased CLI v1 context also exposes only required artifact types even though the workflow contract requires cardinality, subject, and allowed states.

## Requirements

- BOOT-008-REQ-001: Define closed JSON Schemas for version 1 task-type and workflow YAML documents with an explicit schema version.
- BOOT-008-REQ-002: Define initial and terminal statuses, execution mode, transitions, worktree and repository-change policy, instructions, materials, capabilities, and artifact contracts.
- BOOT-008-REQ-003: Support only the typed conditions `always`, `artifact-present`, `artifact-state`, `decision`, and `not-applicable`; prohibit arbitrary expressions and executable code.
- BOOT-008-REQ-004: Use direct repository-relative references to instruction and material files without recursive template descriptors.
- BOOT-008-REQ-005: Reject absolute paths, traversal, references outside `.kos`, symlinks, duplicate YAML keys, aliases, custom tags, unknown fields, and missing members.
- BOOT-008-REQ-006: Define a generated bundle manifest containing workflow identity, version, and the complete sorted closure of member paths and digests.
- BOOT-008-REQ-007: Hash exact member bytes and compute the bundle digest from the RFC 8785 canonical JSON manifest without a self-digest field.
- BOOT-008-REQ-008: Align the unreleased CLI v1 executable context with complete artifact requirements rather than artifact types alone.
- BOOT-008-REQ-009: Provide a complete representative `quick-fix/1.0.0` fixture and negative validation cases.

## Scope

- Update the project configuration, workflow execution, artifact, and draft CLI protocol specifications where required.
- Add version 1 project JSON Schemas for YAML documents and the generated bundle manifest.
- Add representative valid and invalid project-configuration fixtures and contract tests.
- Correct draft CLI v1 schemas, fixtures, and contract tests only where the full artifact requirement is needed.
- Update the external bootstrap plan, commit the verified result, and publish it normally to the default branch.

## Non-Goals

- Implementing a Rails or CLI configuration loader, API endpoints, persistence, or snapshot storage.
- Shipping the production `.kos/quick-fix/1.0.0` bundle assigned to the quick-fix vertical-slice phase.
- Implementing runtime skills, initialization, `feature`, or `initiative` workflows.
- Adding template descriptors, recursive material references, overlays, arbitrary conditions, or replaceable storage backends.

## Related Specifications And ADRs

- [Project Configuration](../../docs/specs/project-configuration.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [ADR-0003: Pinned Project Workflows](../../docs/decisions/0003-pinned-project-workflows.md)

## Task-Local Decisions

- BOOT-008-DEC-001: `implementation-planning` is a subagent technical-planning step for an already approved quick fix; future grooming, requirements, and decomposition statuses own human-facing product clarification.
- BOOT-008-DEC-002: A `changes_requested` review registers evidence and transitions back to `development`; a new candidate requires a new independent review.
- BOOT-008-DEC-003: `completed` is a terminal status without an instruction or attempt.
- BOOT-008-DEC-004: Version 1 uses direct instruction and material file references and has no recursive template descriptor.
- BOOT-008-DEC-005: The generated canonical JSON manifest, excluding any self-digest, is the aggregate bundle digest input.
- BOOT-008-DEC-006: BOOT-008 provides the normative contract and fixtures, not a production workflow bundle.

## Acceptance Criteria

- BOOT-008-AC-001: All project schema documents validate against JSON Schema draft 2020-12 and resolve local references without network access.
- BOOT-008-AC-002: A complete quick-fix fixture passes YAML safety, schema, graph, reference, capability, and artifact validation.
- BOOT-008-AC-003: Negative fixtures cover unsafe YAML and paths, malformed graphs, ambiguous branches, invalid capabilities and artifacts, and incomplete bundles.
- BOOT-008-AC-004: Golden vectors prove exact member hashing, filesystem-order independence, and bundle digest changes for changed bytes, paths, and member sets.
- BOOT-008-AC-005: The draft CLI v1 context represents complete workflow artifact requirements consistently with project schema v1.
- BOOT-008-AC-006: All required project checks pass and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-008 active externally.
2. Define the normative version 1 schema vocabulary, graph semantics, reference rules, and canonical digest algorithm.
3. Add project schemas and complete valid and invalid fixtures.
4. Add contract tests for YAML safety, graph semantics, references, capabilities, artifacts, and digest golden vectors.
5. Align draft CLI v1 artifact requirements and its fixtures and contract tests.
6. Run focused and full test, lint, security, autoloading, and diff checks.
7. Update the external plan, commit the task files, and push normally to the default branch.

## Verification

- Run `bundle exec rspec spec/contracts/project_configuration_v1_contract_spec.rb` while iterating.
- Run `bundle exec rspec`.
- Run `bundle exec rubocop`.
- Run `bin/rails zeitwerk:check`.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Verification Results

- `bundle exec rspec spec/contracts/project_configuration_v1_contract_spec.rb`: 39 examples, 0 failures.
- `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb`: 134 examples, 0 failures.
- `bundle exec rspec`: 174 examples, 0 failures.
- `bundle exec rubocop`: 22 files inspected, no offenses.
- `bin/rails zeitwerk:check`: passed.
- `mise run check`: passed, including Brakeman with no warnings and bundler-audit with no vulnerabilities.
- `git diff --check`: passed.

## Risks

- JSON Schema cannot express every graph and filesystem invariant; the specification and contract assertions must define the remaining semantics.
- RFC 8785 implementations must produce identical bytes; golden vectors pin the exact manifest input and expected digest.
- Runtime handling of requested Git effects remains future work and is not designed by this task.
