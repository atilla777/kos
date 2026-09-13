---
title: Canonical KOS Workflow Step Skill
task: BOOT-035
created: 2026-09-13
---

# BOOT-035: Canonical KOS Workflow Step Skill

## Goal

Add the canonical `kos-workflow-step` skill that executes the exact pinned Markdown instruction from a finalized attempt context and returns only a schema-valid typed effect request or final result manifest.

## User Outcome

A workflow subagent can perform any pinned subagent step without a step-specific runtime skill, request only context-authorized repository effects through its lease-owning orchestrator, and return artifact evidence without directly accessing KOS state or Git.

## Context

OpenCode 1.18.26 already provides the foreground child-session transport and same-session typed effect round trip. The version 1 workflow schema defines the complete finalized context, effect request, effect result, artifact inputs, and result manifest. Canonical `kos-cli` and `kos-repository` skills exist for the orchestrator boundaries but are intentionally unavailable to a workflow-step subagent.

## Requirements

- BOOT-035-REQ-001: Add `skills/kos-workflow-step/SKILL.md` as the sole canonical source with OpenCode-compatible `name` and `description` frontmatter; do not add `skills/index.md`.
- BOOT-035-REQ-002: Accept only the complete finalized version 1 context supplied by the orchestrator and verify its identity and required bindings before execution; never read, infer, repair, or refresh KOS state independently.
- BOOT-035-REQ-003: Execute only the exact pinned instruction, artifact templates, requirements, worktree, and effect allowlist in that context. A pinned instruction cannot weaken the skill's authority and safety boundaries.
- BOOT-035-REQ-004: Prohibit direct access to the `kos` CLI, Rails API, SQLite, Rails persistence, `kos-repository`, all Git commands, and other subagents.
- BOOT-035-REQ-005: When repository files may change, work only inside the allocated task worktree and reject paths or tools that escape it.
- BOOT-035-REQ-006: Request a repository mutation only through an effect request conforming to `workflow.json#/$defs/effect_request`, bound to the context attempt and digest, and selected from `allowed_repository_effects`.
- BOOT-035-REQ-007: Emit exactly one JSON document and no prose, Markdown fence, routing identifier, or wrapper in each child turn. A turn is either one effect request or one final result manifest.
- BOOT-035-REQ-008: After an effect request, accept only the complete version 1 effect result delivered by the orchestrator to the same session and require matching attempt, context digest, request digest, operation, intent, and operation-specific target fields.
- BOOT-035-REQ-009: Treat failed and unknown effect outcomes as explicit evidence. Do not rewrite them as success, retry an effect directly, or fabricate resulting SHAs, digests, observations, or artifacts.
- BOOT-035-REQ-010: Return a final manifest conforming to `workflow.json#/$defs/result_manifest` with the exact attempt ID and context digest, an explicit outcome, and only schema-valid artifacts supported by observed evidence and the pinned requirements.
- BOOT-035-REQ-011: Do not submit the final manifest, mutate workflow state, choose the orchestrator's transition command, or claim another attempt; the lease-owning orchestrator alone submits the unchanged substantive result.
- BOOT-035-REQ-012: Add deterministic contract coverage for frontmatter, authority and worktree boundaries, context handling, effect/result state transitions, exact output rules, schema inventories, and OpenCode 1.18.26 discovery.
- BOOT-035-REQ-013: Preserve runtime transport, CLI, API, workflow schemas, repository adapter, Git, persistence, and publication behavior.

## Scope

- The canonical `kos-workflow-step` skill.
- A focused static, schema-derived, and pinned-OpenCode discovery contract.
- This task record and external bootstrap plan updates.

## Non-Goals

- Implementing `kos-orchestrate`, initialization, installation, retrospective, or the operational quick-fix workflow.
- Changing JSON schemas, runtime transport, CLI/API commands, repository-adapter operations, or persistence.
- Automatic skill installation or runtime permission enforcement.
- Proving that an arbitrary model follows the skill instructions.

## Related Specifications And ADRs

- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)

## Task-Local Decisions

- BOOT-035-DEC-001: The skill receives one already-finalized context from its orchestrator. Context acquisition, lease renewal, and state freshness remain orchestrator responsibilities.
- BOOT-035-DEC-002: A child turn contains only the nested version 1 KOS document. OpenCode wrapper and child-session identity are runtime-adapter concerns and never fields invented by the subagent.
- BOOT-035-DEC-003: The executor may produce sequential effect-request turns when the pinned context allows them, but only one request may be pending and every result must be validated before another request or final manifest.
- BOOT-035-DEC-004: Effect success is observed evidence, not permission to invent an artifact or successful step outcome; the pinned instruction and artifact contract still govern the final manifest.

## Acceptance Criteria

- BOOT-035-AC-001: `skills/kos-workflow-step/SKILL.md` exists with valid identifying frontmatter and no canonical skill index is added.
- BOOT-035-AC-002: A test-time installed copy is discovered by pinned OpenCode 1.18.26 from a nested worktree directory.
- BOOT-035-AC-003: The skill accepts only finalized attempt-bound context and preserves its attempt and digest in every output.
- BOOT-035-AC-004: The skill prohibits direct KOS state, Git, repository-adapter, and subagent access and limits filesystem work to the allocated worktree.
- BOOT-035-AC-005: Every child turn is exactly one schema-valid effect request or final result manifest without prose or runtime routing data.
- BOOT-035-AC-006: Effect requests are allowlisted and effect results are completely identity-, digest-, operation-, intent-, and target-bound before use.
- BOOT-035-AC-007: Failed, unknown, malformed, or mismatched effect results fail closed and cannot produce fabricated success evidence.
- BOOT-035-AC-008: The orchestrator remains the only actor that submits the final manifest or mutates workflow state.
- BOOT-035-AC-009: Focused skill, workflow-schema, CLI, and runtime contracts, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-035 active externally.
2. Add the self-contained canonical skill with context, authority, execution, effect exchange, artifact, and output guidance.
3. Add schema-derived static contracts and install the canonical file into an isolated OpenCode fixture for real pinned-runtime discovery.
4. Run focused workflow-step and affected runtime/schema contracts, then the complete project checks and whitespace validation.
5. Record verification and implementation results, update the external plan, review the diff, commit only task files, and push normally to `main`.

## Verification

- Run the focused `kos-workflow-step` skill contract while iterating.
- Run the affected workflow-schema, CLI, and OpenCode runtime contracts.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-13:

- `bundle exec rspec spec/contracts/kos_workflow_step_skill_contract_spec.rb` passed with 8 examples and no failures.
- The focused workflow-step and OpenCode runtime contracts passed together with 14 examples and no failures after the final recovery change; the broader affected workflow schema, runtime, CLI skill, and repository skill contracts passed together with 118 examples and no failures before that change.
- Final `mise run check` passed with 608 examples and no failures, 160 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent correctness, security, and test reviews verified context-digest recomputation, worktree and authority isolation, owner and durable-intent binding, synchronized schema inventories, duplicate detection, and protocol-valid unknown-effect recovery. No high- or medium-severity findings remained.

## Implementation Result

- Added `skills/kos-workflow-step/SKILL.md` as the generic executor for finalized pinned version 1 contexts, independent of step-specific runtime skills.
- Prohibited direct KOS state, Git, repository-adapter, and subagent access while limiting repository file work to the exact allocated worktree.
- Defined the closed child-turn state machine for allowlisted typed effect requests, fully bound effect results, evidence-backed artifacts, and unchanged final result manifests.
- Made malformed context fail before execution, required RFC 8785 context and effect digest checks, and routed unknown effects to authoritative recovery without inventing success or prescribing invalid publication ordering.
- Added a contract derived from the workflow and artifact schemas that checks exact request, allowlist, result, outcome, and artifact inventories; required safety guidance; complete result binding; duplicate resistance; and isolated nested-directory discovery with OpenCode 1.18.26.
- Preserved runtime transport, CLI, API, schemas, repository adapter, Git, persistence, and publication behavior.

## Risks

- Skill instructions are procedural guidance rather than a runtime security boundary; installation and orchestrator permissions must enforce the declared authority.
- The complete operational round trip depends on the later `kos-orchestrate` skill.
- Static contracts cannot prove that an arbitrary model obeys the skill or identify every contradictory prose edit.
