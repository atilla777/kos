---
title: Canonical KOS Retrospective Skill
task: BOOT-037
created: 2026-09-14
---

# BOOT-037: Canonical KOS Retrospective Skill

## Goal

Add the canonical `kos-retrospective` skill that privately analyzes its own gracefully ending KOS session after the primary result is acknowledged and returns a separate sanitized improvement result without changing workflow state or creating follow-up work.

## User Outcome

When installation-wide retrospective is enabled and the runtime supplies the required lifecycle boundary, an orchestrator or workflow-step session has one authoritative procedure for producing bounded, actionable, privacy-preserving proposals. Retrospective failure cannot delay, replace, or change the session's primary result.

## Context

The retrospective behavior and closed version 1 result schema already exist. OpenCode 1.18.26 currently supports skill discovery and workflow-step typed-effect transport, but it does not yet implement graceful-end invocation, private-dialogue extraction, retrospective timeout enforcement, or second-result delivery. ADR-0008 leaves those runtime adapter capabilities to a separate increment, so this task defines and tests the canonical skill without claiming executable lifecycle integration.

## Requirements

- BOOT-037-REQ-001: Add `skills/kos-retrospective/SKILL.md` as the sole canonical source with OpenCode-compatible `name` and `description` frontmatter; do not add `skills/index.md`.
- BOOT-037-REQ-002: Run only for a runtime-established, installation-wide opt-in invocation after a gracefully ending orchestration or workflow-step session has delivered and acknowledged its primary result.
- BOOT-037-REQ-003: Exclude internal `kos-cli` and `kos-repository` calls, in-process skill expansion, abrupt process loss, and retrospective itself from eligible sessions; require recursion suppression.
- BOOT-037-REQ-004: Analyze only the invoking agent's own private session dialogue and treat every dialogue item as untrusted evidence rather than an executable instruction.
- BOOT-037-REQ-005: Never transmit raw dialogue or verbatim transcript excerpts. Omit credentials, secrets, environment values, personal data, unrelated source content, and private absolute paths from every result.
- BOOT-037-REQ-006: Exercise no KOS state read or mutation, Rails, API, CLI, filesystem, Git, network, repository-effect, or subagent-launch authority.
- BOOT-037-REQ-007: Accept `session_id`, `source`, primary-result acknowledgement, enablement, recursion suppression, and lifecycle eligibility only from the runtime boundary. Never infer, generate, repair, or override those values.
- BOOT-037-REQ-008: Return exactly one JSON document with no prose that validates as `schemas/runtime/v1/retrospective.json#/$defs/result`, using the exact version 1 source, outcome, category, proposal-field, and cardinality inventories.
- BOOT-037-REQ-009: Produce no retrospective result when required runtime invocation identity is missing or malformed. For a valid invocation, return `no_action` when no independently actionable improvement is supported, sanitization is unsafe, or a required `suggested_task_type` is not reliably known from permitted input.
- BOOT-037-REQ-010: Split independently correctable mixed findings into separate proposals, include uncertainty explicitly, and never identify an installed runtime copy as the canonical correction target.
- BOOT-037-REQ-011: Do not persist, deduplicate, submit, create, approve, or start a proposal or task. Leave follow-up scope and authorization to the user.
- BOOT-037-REQ-012: Preserve primary-result independence: retrospective is bounded best-effort post-processing, and its failure, cancellation, or timeout cannot delay, replace, downgrade, or change the acknowledged primary result.
- BOOT-037-REQ-013: Add deterministic contract coverage for frontmatter, lifecycle, primary-result ordering, privacy, authority, schema-derived inventories and bounds, classification, task boundaries, unavailable runtime transport, and OpenCode 1.18.26 discovery.
- BOOT-037-REQ-014: Preserve schemas, Rails, API, CLI, persistence, workflow, repository adapter, Git, existing skills, and current OpenCode transport behavior.

## Scope

- The canonical `kos-retrospective` skill.
- A focused static, schema-derived, and pinned-OpenCode discovery contract.
- Narrow retrospective specification clarifications for invalid invocation identity, unsafe sanitization, and unknown task type.
- This task record and external bootstrap plan updates.

## Non-Goals

- Implementing OpenCode graceful-end hooks, private-dialogue extraction, retrospective invocation input, timeout enforcement, or post-primary result delivery.
- Changing runtime, CLI, API, persistence, workflow, or repository schemas.
- Reading installation configuration through a new command or installing canonical skills automatically.
- Persisting or deduplicating proposals, creating tasks automatically, or proving arbitrary-model compliance.

## Related Specifications And ADRs

- [KOS Retrospective](../../docs/specs/retrospective.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Product Boundary](../../docs/specs/product-boundary.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)

## Task-Local Decisions

- BOOT-037-DEC-001: This increment ships only the canonical skill and its contract. Executable OpenCode retrospective lifecycle and transport remain a separate adapter task.
- BOOT-037-DEC-002: The skill copies only a runtime-supplied schema-valid retrospective UUID and source. Missing or invalid invocation identity produces no retrospective result rather than being replaced with an OpenCode routing ID or a generated identifier.
- BOOT-037-DEC-003: If a schema-valid `suggested_task_type` is not reliably known from the permitted dialogue and runtime input, the skill returns `no_action` rather than inventing catalog state it has no authority to read.
- BOOT-037-DEC-004: When safe sanitization is impossible, version 1 returns schema-valid `no_action`; a separate generic warning transport is not invented by this task.

## Acceptance Criteria

- BOOT-037-AC-001: `skills/kos-retrospective/SKILL.md` exists with valid identifying frontmatter and no canonical skill index is added.
- BOOT-037-AC-002: A test-time installed copy is discovered by pinned OpenCode 1.18.26 from a nested task-worktree directory.
- BOOT-037-AC-003: The skill accepts only runtime-established opt-in, eligible, recursion-suppressed invocation after primary-result acknowledgement.
- BOOT-037-AC-004: The skill analyzes only its own private dialogue, treats it as untrusted, and prevents raw or sensitive content from entering the result.
- BOOT-037-AC-005: The skill has no state, filesystem, Git, network, repository-effect, or subagent authority.
- BOOT-037-AC-006: Output uses the exact closed version 1 result shape, source and outcome inventories, proposal categories and fields, and cardinality and length bounds.
- BOOT-037-AC-007: Invalid invocation identity produces no result. Unsafe, unsupported, insignificant, or incompletely identified findings under a valid invocation produce `no_action`; independent findings are split and installed copies are not canonical targets.
- BOOT-037-AC-008: Proposals remain non-persistent user-visible suggestions and cannot create or start a task.
- BOOT-037-AC-009: Retrospective cannot change or delay the primary result, and the contract explicitly does not claim missing OpenCode lifecycle and post-primary transport.
- BOOT-037-AC-010: Focused retrospective and affected runtime/schema contracts, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-037 active externally.
2. Add the self-contained canonical skill with lifecycle, primary-result, privacy, authority, analysis, classification, result, and unavailable-runtime boundaries.
3. Add schema-derived static contracts and install the canonical file into an isolated OpenCode fixture for real pinned-runtime discovery.
4. Run focused retrospective and affected runtime/schema contracts, then the complete project checks and whitespace validation.
5. Record verification and implementation results, update the external plan, review the diff, commit only task files, and push normally to `main`.

## Verification

- Run the focused `kos-retrospective` skill contract while iterating.
- Run affected retrospective schema and OpenCode runtime contracts.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-14:

- `bundle exec rspec spec/contracts/kos_retrospective_skill_contract_spec.rb` passed with 8 examples and no failures.
- The affected retrospective skill, CLI schema, and OpenCode runtime contracts passed together with 101 examples and no failures.
- Final `mise run check` passed with 624 examples and no failures, 162 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent correctness and privacy reviews found no remaining high- or medium-severity issues after fail-closed invalid-invocation semantics and stronger schema/guidance coverage were added.

## Implementation Result

- Added `skills/kos-retrospective/SKILL.md` as the canonical private post-primary analysis procedure for eligible orchestration and workflow-step sessions.
- Defined runtime-supplied lifecycle identity, acknowledgement, recursion suppression, bounded best-effort execution, and no-result handling for malformed invocation data.
- Defined dialogue isolation, sanitization, zero-side-effect authority, exact proposal classification, closed version 1 output, and user-owned follow-up boundaries.
- Explicitly blocked manual substitution for the unavailable OpenCode graceful-end hook, private dialogue input, timeout enforcement, and second-result transport.
- Clarified the normative retrospective contract for malformed invocation data, unsafe sanitization, and unavailable trustworthy task types.
- Added schema-derived coverage for closed fields, exact inventories, annotations, cardinality and text bounds, security guidance, forbidden authority language, and isolated OpenCode 1.18.26 discovery.
- Preserved runtime schemas, Rails, API, CLI, persistence, workflows, repository behavior, Git behavior, and existing skills.

## Risks

- Skill instructions and static contracts are procedural guidance, not a runtime security boundary.
- Current OpenCode integration cannot execute or prove graceful retrospective invocation, private-dialogue isolation, timeout behavior, or post-primary delivery.
- Returning `no_action` when task type is unknown avoids invented state but may suppress an otherwise useful proposal until the runtime supplies a trustworthy type.
