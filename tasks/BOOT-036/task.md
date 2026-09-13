---
title: Canonical KOS Orchestrator Skill
task: BOOT-036
created: 2026-09-13
---

# BOOT-036: Canonical KOS Orchestrator Skill

## Goal

Add the canonical `kos-orchestrate` skill that coordinates one pinned workflow status as the lease-owning main session, mediates the generic workflow-step subagent and durable typed repository effects, and submits the executor's unchanged substantive result when the implemented protocol permits it.

## User Outcome

An OpenCode main session can follow one authoritative orchestration procedure for attempt ownership, pinned context, foreground child transport, repository-effect mediation, and result submission without bypassing KOS state or Git boundaries. Missing operational protocol surfaces stop safely rather than being guessed or simulated.

## Context

Canonical `kos-cli`, `kos-repository`, and `kos-workflow-step` skills already define the state, Git-adapter, and generic executor boundaries. OpenCode 1.18.26 provides the guarded foreground child-session transport and typed effect round trip. The current CLI does not yet expose `publication complete`, a complete repository snapshot for every adapter request, or a generic adapter observation operation for unknown commit, fetch, and rebase effects, so this task cannot truthfully complete the operational quick-fix vertical slice.

## Requirements

- BOOT-036-REQ-001: Add `skills/kos-orchestrate/SKILL.md` as the sole canonical source with OpenCode-compatible `name` and `description` frontmatter; do not add `skills/index.md`.
- BOOT-036-REQ-002: Start only from an explicit immutable repository ID and public task number, read all workflow state through `kos`, and never infer, repair, or substitute scope, identity, version, ownership, path, Git, transition, or durable-resource values.
- BOOT-036-REQ-003: Read the task and its pinned workflow version, reconcile an expired attempt before claiming, retain one idempotency key and exact body per logical mutation, and use only a current lease, lock version, and fencing token for attempt-owned work.
- BOOT-036-REQ-004: Stop attempt-owned mutation and repository work immediately on lease or fencing loss. Reread authoritative state after conflicts or a foreground child turn and never blindly retry a mutation or external effect.
- BOOT-036-REQ-005: Coordinate required worktree reservation, materialization, observation, confirmation, adoption, and cleanup only through the existing durable state and repository-adapter protocols and only when complete fresh authoritative snapshots are available.
- BOOT-036-REQ-006: Prepare or adopt a publication before publication context finalization when the implemented protocol supplies all required inputs. Never invent an expected remote OID, review, check, candidate, target, or completion operation.
- BOOT-036-REQ-007: Finalize one attempt-bound version 1 context through `kos step context`; validate its complete schema, identities, pinned workflow status, lease and fencing values, worktree and publication bindings, and RFC 8785 input-context digest before execution.
- BOOT-036-REQ-008: Read `execution_mode` only from the task's pinned workflow definition. Execute main-session statuses in the orchestrator and launch `kos-workflow-step` for subagent statuses without substituting a step-specific skill.
- BOOT-036-REQ-009: For an OpenCode subagent status, use one foreground Task child in the reserved task worktree, obtain its opaque session ID only from the runtime-generated completed wrapper, cross-check event metadata, retain it only as routing state, and continue exactly that child after an effect result.
- BOOT-036-REQ-010: Accept each child turn only as one schema-valid effect request or result manifest with no mixed prose. Fail closed on malformed wrappers, unexpected turn order, changed child identity, or mismatched attempt, context digest, operation, intent, or target.
- BOOT-036-REQ-011: Accept an effect request only when it is present in the frozen allowlist and every operation-specific precondition matches fresh KOS state and the finalized context.
- BOOT-036-REQ-012: For `commit`, `fetch`, and `rebase`, follow durable `effect prepare -> kos-repository -> effect reconcile`; for `worktree_remove` and `push`, follow their reservation and publication protocols. Reconcile every usable typed result before returning it unchanged to the same child.
- BOOT-036-REQ-013: Preserve failed and unknown external outcomes, never fabricate an observation or success, never create a replacement intent after uncertainty, and enter authoritative recovery when the current version 1 surfaces cannot safely reconcile the effect.
- BOOT-036-REQ-014: Validate a final manifest against the frozen attempt and context, preserve its substantive outcome and evidence unchanged, select only an unambiguous transition declared by the pinned workflow, and submit it through `attempt fail`, `attempt needs-human`, `step complete`, or an implemented specialized completion command as applicable.
- BOOT-036-REQ-015: Do not invoke unavailable commands, including `publication complete`, or bypass them through Rails, the API, SQLite, direct Git, source-checkout executables, or invented adapter operations. Block safely when an authoritative repository snapshot, generic-effect recovery observation, transition decision, or completion command is unavailable.
- BOOT-036-REQ-016: Add deterministic contract coverage for frontmatter, authority and ownership, state acquisition, context and workflow binding, OpenCode child routing, effect mediation, result submission, unavailable boundaries, schema inventories, and OpenCode 1.18.26 discovery.
- BOOT-036-REQ-017: Preserve CLI, API, runtime transport, workflow schemas, repository adapter, Git, persistence, publication, and workflow behavior.

## Scope

- The canonical `kos-orchestrate` skill.
- A focused static, schema-derived, and pinned-OpenCode discovery contract.
- This task record and external bootstrap plan updates.

## Non-Goals

- Implementing new CLI/API commands, JSON schemas, persistence, or repository-adapter operations.
- Implementing `publication complete`, repository snapshot reads, generic-effect observation, background lease renewal, or the complete quick-fix vertical slice.
- Implementing initialization, installation, retrospective, or runtime permission enforcement.
- Proving that an arbitrary model follows skill instructions.

## Related Specifications And ADRs

- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Publication](../../docs/specs/publication.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)

## Task-Local Decisions

- BOOT-036-DEC-001: This task ships the complete canonical orchestration procedure but does not claim an operational end-to-end quick-fix slice. A missing command or authoritative snapshot is a fail-closed boundary for a later operational task.
- BOOT-036-DEC-002: One invocation coordinates one current workflow status. A later status requires a fresh state evaluation and claim rather than recursively extending the frozen attempt context.
- BOOT-036-DEC-003: The child result manifest remains the executor's substantive result. The orchestrator validates it and chooses the matching protocol command but never rewrites its outcome, artifacts, summary, or evidence.
- BOOT-036-DEC-004: A foreground child may outlive the lease because background renewal is not implemented. The orchestrator rereads ownership after every child turn and performs no further attempt-owned operation when freshness cannot be established; this task does not claim continuous lease enforcement during the blocked turn.

## Acceptance Criteria

- BOOT-036-AC-001: `skills/kos-orchestrate/SKILL.md` exists with valid identifying frontmatter and no canonical skill index is added.
- BOOT-036-AC-002: A test-time installed copy is discovered by pinned OpenCode 1.18.26 from a nested task-worktree directory.
- BOOT-036-AC-003: The skill establishes explicit repository/task scope, pinned workflow authority, attempt reconciliation and claim, lease/fencing freshness, and idempotent mutation handling without direct state or Git access.
- BOOT-036-AC-004: The skill validates the complete finalized context and dispatches only its pinned `execution_mode` through the correct main-session or foreground-child path.
- BOOT-036-AC-005: Child routing retains only the runtime-generated session ID and fails closed on malformed, mixed, changed, unexpected, or mismatched turns.
- BOOT-036-AC-006: Every version 1 effect uses its allowlisted durable protocol and only a reconciled, fully bound result returns to the same child.
- BOOT-036-AC-007: Failed, unknown, unavailable, stale, or incomplete operations cannot become fabricated success, duplicate external effects, or bypassed state changes.
- BOOT-036-AC-008: A final manifest is submitted without substantive rewriting and only through an unambiguous pinned transition and implemented command.
- BOOT-036-AC-009: The contract explicitly blocks unavailable publication completion, incomplete repository snapshots, generic unknown-effect observation, and continuous foreground-child lease renewal.
- BOOT-036-AC-010: Focused orchestration and affected skill/runtime/schema contracts, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-036 active externally.
2. Add the self-contained canonical skill with authority, attempt, worktree, context, runtime routing, durable-effect, result-submission, and fail-closed recovery guidance.
3. Add schema-derived static contracts and install the canonical file into an isolated OpenCode fixture for real pinned-runtime discovery.
4. Run focused orchestrator and affected skill/runtime/schema contracts, then the complete project checks and whitespace validation.
5. Record verification and implementation results, update the external plan, review the diff, commit only task files, and push normally to `main`.

## Verification

- Run the focused `kos-orchestrate` skill contract while iterating.
- Run the affected CLI, repository, workflow-step, workflow-schema, and OpenCode runtime contracts.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-13:

- `bundle exec rspec spec/contracts/kos_orchestrate_skill_contract_spec.rb` passed with 8 examples and no failures.
- The affected CLI, repository, workflow-step, orchestrator, OpenCode runtime, CLI schema, and repository schema contracts passed together with 154 examples and no failures.
- Final `mise run check` passed with 616 examples and no failures, 161 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent correctness and security reviews verified fail-closed generic-effect discovery, authoritative worktree-path handling, specialized worktree and publication reconciliation, lease budget, artifact pagination, and composition with the executable OpenCode transport contract. No high- or medium-severity findings remained.

## Implementation Result

- Added `skills/kos-orchestrate/SKILL.md` as the lease-owning main-session procedure for one pinned workflow status.
- Defined authoritative task and workflow reads, expired-attempt handling, idempotent claim and renewal, worktree and publication preparation, finalized-context validation, and post-child ownership checks.
- Defined pinned `main_session` and guarded foreground `subagent` dispatch with runtime-wrapper child identity, exact-turn validation, and same-session effect delivery.
- Mapped every version 1 repository effect to its durable state and adapter protocol, including specialized worktree-removal and publication recovery and explicit blocking for unresolved or unobservable effects.
- Preserved executor manifests unchanged while limiting submission to one fully evidenced pinned transition and an implemented completion command.
- Explicitly blocked publication completion, new worktree allocation, adopted generic-effect discovery, incomplete repository snapshots, generic unknown-effect observation, and continuous foreground-child lease renewal where current operational surfaces are absent.
- Added a schema-derived static contract for mode and effect inventories, required authority and recovery guidance, implemented command availability, fail-closed boundaries, and isolated OpenCode 1.18.26 discovery.
- Preserved CLI, API, schemas, runtime transport, repository adapter, Git, persistence, publication, and workflow behavior.

## Risks

- Skill instructions are procedural guidance rather than a runtime security boundary; installation must later enforce the declared authority.
- OpenCode foreground Task execution has no implemented concurrent lease keeper. A lease may expire while the parent is blocked, so post-turn freshness validation prevents further mutation but cannot prevent child file edits after expiry.
- The current CLI cannot complete publication, allocate a new worktree path, enumerate adopted generic effects, or supply every fresh adapter snapshot, and version 1 has no generic adapter observation operation. Those paths remain intentionally blocked.
- Static contracts cannot prove that an arbitrary model obeys the skill or identify every contradictory prose edit.
