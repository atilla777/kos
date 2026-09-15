---
title: Independent Candidate Review Attempt
task: BOOT-045
created: 2026-09-15
status: completed
---

# BOOT-045: Independent Candidate Review Attempt

## Goal

Make the `quick-fix@1.0.1` review status operational through an independent attempt that verifies the exact unchanged candidate and atomically routes an approved review to publication or requested changes back to development.

## User Outcome

A reviewer examines the exact candidate produced and tested by development. KOS accepts one candidate-bound `approved` or `changes_requested` artifact only while the supplied worktree remains clean at that candidate, then records the review and transition atomically.

## Context

The workflow catalog, review artifact shape, both review transitions, candidate-generation validation, and distinct-attempt check already exist. The missing operational boundary is a fresh worktree observation owned by the review attempt: after reservation adoption, the durable observation can still describe development's fencing token, and review completion does not currently verify the frozen candidate against the current clean worktree.

## Requirements

- BOOT-045-REQ-001: A review attempt must be distinct from the succeeded attempt that produced the current candidate.
- BOOT-045-REQ-002: Before dispatching review, observe the confirmed worktree under the review attempt's fencing token at the exact current candidate SHA and durably reconcile the clean observation.
- BOOT-045-REQ-003: A frozen review context must bind the current candidate, confirmed reservation HEAD, and fresh clean observation for the review attempt to the same SHA.
- BOOT-045-REQ-004: Review permits no repository effects and must not change repository files.
- BOOT-045-REQ-005: After the reviewer returns and before completion, repeat the exact-candidate observation and reconcile it under the current review ownership.
- BOOT-045-REQ-006: Review completion must require equality among the frozen candidate, frozen and current reservation HEAD, current candidate generation, review artifact candidate, and latest clean observation owned by the review fencing token.
- BOOT-045-REQ-007: Exactly one review artifact names the current review attempt and routes `changes_requested` to development or `approved` to publication atomically.
- BOOT-045-REQ-008: Dirty, mismatched, absent, stale, malformed, wrong-generation, wrong-attempt, duplicate, or contradictory evidence must not advance the review status.
- BOOT-045-REQ-009: Preserve published workflow versions and existing planning, development, publication, persistence, API, CLI, and repository-adapter contracts outside this review boundary.

## Scope

- Review-specific context and completion guards using the existing worktree observation and reconciliation protocol.
- Canonical observation-evidence verification shared with the repository adapter without a persistence migration.
- Canonical orchestration guidance and required runtime installation integrity update.
- Workflow, artifact, and CLI specification updates for the exact-candidate review boundary.
- Focused service, request, skill-contract, and real-Git vertical integration coverage for both verdicts and unsafe observations.

## Non-Goals

- Reviewer identity stronger than a distinct workflow attempt.
- New structured review-finding fields or a required findings document.
- Publication completion, publication orchestration, or complete quick-fix E2E execution.
- A new workflow version, endpoint, CLI command, dependency, migration, or ADR.
- Background lease renewal while the foreground reviewer runs.

## Related Specifications And ADRs

- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Artifact Contracts](../../docs/specs/artifact-contracts.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Publication](../../docs/specs/publication.md)
- [ADR-0002](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-045-DEC-001: Verify the exact candidate with fresh clean observations both before dispatch and after the reviewer result, rather than relying only on SHA equality or development's prior observation.
- BOOT-045-DEC-002: Prove observation ownership and ordering without a migration by adding a server-generated unpredictable nonce to the frozen review context and validating the post-context adapter evidence digest against the resulting input-context digest, current reservation identity, review fencing token, path, branch, state, HEAD, and common-directory digest.
- BOOT-045-DEC-003: Keep independence attempt-based as defined by the accepted artifact contract; actor, model, and human identity are outside this task.
- BOOT-045-DEC-004: Keep findings in the immutable review attempt result manifest and retain the existing closed review artifact metadata.

## Acceptance Criteria

- BOOT-045-AC-001: A fresh review attempt receives a context whose candidate SHA and worktree HEAD equal the current succeeded development candidate.
- BOOT-045-AC-002: A clean exact candidate can register one `approved` review and transition to publication.
- BOOT-045-AC-003: A clean exact candidate can register one `changes_requested` review and transition back to development.
- BOOT-045-AC-004: Both routes persist the exact candidate SHA and current review attempt ID, succeed the attempt, create no review repository effect, and leave the reservation at the candidate SHA.
- BOOT-045-AC-005: A stale prior observation, dirty or mismatched post-review worktree, wrong candidate generation, wrong review attempt, duplicate review, or self-review cannot complete the step.
- BOOT-045-AC-006: Focused checks, `mise run check`, `git diff --check`, and independent review pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-045 active externally.
2. Add a canonical worktree observation-evidence digest boundary and use it to require a current review-owned clean candidate observation during context capture and completion.
3. Bind review artifacts to the frozen candidate, current candidate generation, and frozen and current reservation HEAD while preserving existing atomic transition behavior.
4. Update canonical orchestration guidance to observe and reconcile the exact candidate before reviewer dispatch and after its result.
5. Update affected behavioral specifications and runtime installation integrity data without changing the published workflow.
6. Extend focused service and request coverage plus the real-Git vertical flow through both review outcomes and failure cases.
7. Run focused and full verification, validate the diff, and obtain independent review.
8. Record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused workflow context/completion, worktree evidence, request, schema, skill, runtime installation, and real-Git integration specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Completed verification on 2026-09-15:

- Focused review context, completion, REST, adapter schema, runtime skill, installation, and real-Git suites passed with 300 examples and no failures.
- Final `mise run check` passed with 758 examples and no failures, 195 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent review found and prompted fixes for post-context observation ordering and replay resistance. Final re-review found no remaining correctness, security, reliability, compatibility, or test findings.

## Implementation Result

- Review context capture now requires the current candidate at a clean confirmed reservation HEAD under the review attempt's fencing token.
- Initial capture consumes the pre-review observation and adds an unpredictable server nonce to the frozen context. Post-review adapter evidence binds the resulting input-context digest, preventing omitted or replayed pre-context observations from satisfying completion.
- Review completion now requires the frozen candidate, current generation, review artifact, reservation, context-bound clean observation, and distinct review attempt to agree, while rejecting review-owned repository effects.
- Canonical orchestration guidance now performs observe/reconcile before reviewer dispatch and after its result without changing the published workflow version.
- Real-Git coverage now reaches both `approved -> publication` and `changes_requested -> development` outcomes and rejects dirty post-review state.

## Risks

- Git cannot atomically enforce a KOS fencing token while the child runs. Fresh observations detect changed final state but cannot prevent an edit made during review.
- A repository change followed by an exact restoration may not be visible in the final clean observation; this task guarantees the reviewed final tree and HEAD, not a complete filesystem event audit.
- Skill instructions and static contracts cannot prove compliance by every model, so backend completion remains fail-closed on the final durable evidence.
