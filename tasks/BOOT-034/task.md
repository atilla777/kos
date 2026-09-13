---
title: Canonical KOS Repository Skill
task: BOOT-034
created: 2026-09-13
---

# BOOT-034: Canonical KOS Repository Skill

## Goal

Add the canonical `kos-repository` skill that teaches the lease-owning orchestrator to execute only persisted typed Git effects through the closed repository adapter contract, validate state bindings, and return bounded observations without making workflow decisions.

## User Outcome

The orchestrator can safely invoke the implemented worktree, commit, fetch, rebase, and push operations, validate their version 1 results, and pass observations to the matching durable reconciliation protocol without blind retries or delegated Git authority.

## Context

The local repository adapter already implements a closed version 1 JSON contract for `materialize`, `observe`, `remove`, `commit`, `fetch`, `rebase`, and `push`. It validates request consistency and repository state locally but does not call Rails, establish that supplied ownership is current, or decide whether an observation completes a workflow operation.

## Requirements

- BOOT-034-REQ-001: Add `skills/kos-repository/SKILL.md` as the sole canonical source with OpenCode-compatible `name` and `description` frontmatter; do not add `skills/index.md`.
- BOOT-034-REQ-002: Use the installed `kos-repository <operation> --input <path|-> --json` executable independently of a KOS source checkout.
- BOOT-034-REQ-003: Permit invocation only by the lease-owning orchestrator. A workflow-step subagent may request an allowed typed effect but must not invoke the adapter or Git itself.
- BOOT-034-REQ-004: Before invocation, require authoritative KOS reads and validation of the active task and lock version, attempt, lease, fencing token, and matching reservation, effect, or publication intent; require finalized input context and effect allowlist when the operation is a workflow-requested effect.
- BOOT-034-REQ-005: Require `commit`, `fetch`, and `rebase` to have a prepared durable generic effect; require worktree and push operations to follow their durable reservation and publication protocols.
- BOOT-034-REQ-006: Construct requests only from fresh authoritative snapshots and never infer or repair identities, paths, refs, commits, digests, ownership, fencing values, or transitions.
- BOOT-034-REQ-007: Describe exactly the seven implemented operations and accept only closed version 1 request and result documents.
- BOOT-034-REQ-008: Pass process arguments without shell interpolation, keep stdout and stderr separate, and validate exit status, schema version, operation, outcome, result schema, and all returned identity, digest, and fencing bindings before using a result.
- BOOT-034-REQ-009: Treat adapter success as an observation rather than workflow completion. In particular, a successful push result with `candidate_reachable: false` must be reconciled rather than treated as publication success.
- BOOT-034-REQ-010: Preserve explicit failures and unknown outcomes for durable recovery. Never blindly repeat a mutating operation after a timeout, transient response, or uncertain result; after `push_state_uncertain`, permit a later push invocation only through the authoritative publication recovery path whose adapter preflight first observes remote state.
- BOOT-034-REQ-011: Do not claim that worktree `observe` reconciles generic effects or that the adapter independently proves current Rails ownership and fencing authority.
- BOOT-034-REQ-012: Add deterministic contract coverage for frontmatter, exact operation inventory, authority and state guidance, result and error handling, and OpenCode 1.18.26 discovery.
- BOOT-034-REQ-013: Preserve CLI, API, repository adapter, schema, Git, workflow, and publication behavior.

## Scope

- The canonical `kos-repository` skill.
- A focused static and pinned-OpenCode discovery contract.
- This task record and external bootstrap plan updates.

## Non-Goals

- Implementing orchestration or workflow-step skills.
- Adding adapter operations, request fields, error codes, or retry behavior.
- Changing reservation, generic-effect, publication, or reconciliation protocols.
- Automatic skill installation or runtime permission enforcement.
- Running project checks or making workflow decisions inside the repository adapter.

## Related Specifications And ADRs

- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Publication](../../docs/specs/publication.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)

## Task-Local Decisions

- BOOT-034-DEC-001: The canonical skill invokes the installed `kos-repository` executable; repository-local `bin/kos-repository` remains a development entrypoint.
- BOOT-034-DEC-002: Adapter success is a validated Git observation that must still pass the operation's durable KOS reconciliation protocol.
- BOOT-034-DEC-003: The adapter validates supplied snapshot consistency but the orchestrator establishes current authority through `kos` immediately before invocation.
- BOOT-034-DEC-004: The skill documents no generic adapter observation operation because version 1 exposes only worktree `observe`.

## Acceptance Criteria

- BOOT-034-AC-001: `skills/kos-repository/SKILL.md` exists with valid identifying frontmatter and no canonical skill index is added.
- BOOT-034-AC-002: A test-time installed copy is discovered by pinned OpenCode 1.18.26 from a nested worktree directory.
- BOOT-034-AC-003: The skill lists exactly the seven implemented operations and their valid invocation form.
- BOOT-034-AC-004: The skill establishes lease-owning orchestrator authority, durable-intent preconditions, fresh-state requirements, and separation from workflow policy and direct subagent Git access.
- BOOT-034-AC-005: The skill requires complete result and state-binding validation before any adapter observation is consumed.
- BOOT-034-AC-006: The skill preserves failed and unknown outcomes, distinguishes push reachability from process success, and prohibits blind mutation retries.
- BOOT-034-AC-007: Focused skill, repository, CLI, and runtime contracts, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-034 active externally.
2. Add the self-contained canonical skill with authority, invocation, request, validation, and recovery guidance.
3. Add static contract checks and install the canonical file into an isolated OpenCode fixture for real pinned-runtime discovery.
4. Run focused repository and runtime contracts, then the complete project checks and whitespace validation.
5. Record verification and implementation results, update the external plan, review the diff, commit only task files, and push normally to `main`.

## Verification

- Run the focused `kos-repository` skill contract while iterating.
- Run the affected repository schema, adapter, CLI skill, and OpenCode runtime contracts.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-13:

- `bundle exec rspec spec/contracts/kos_repository_skill_contract_spec.rb` passed with 9 examples and no failures.
- The focused skill, repository schema, repository adapter, CLI skill, and OpenCode runtime contracts passed together with 147 examples and no failures.
- Final `mise run check` passed with 600 examples and no failures, 159 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent safety and test reviews verified push authorization freshness, pre-context worktree handling, `worktree_remove` translation, exact reconciliation envelopes, unknown-push recovery, exact operation inventory, deterministic discovery isolation, and structured coverage of authority, validation, and recovery guidance. No high- or medium-severity findings remained.

## Implementation Result

- Added the canonical `kos-repository` skill for the installed closed version 1 adapter with exact invocation and seven-operation inventory.
- Restricted adapter use to the lease-owning orchestrator, with fresh KOS state, durable intent, fencing, context, allowlist, and operation-specific authority checks.
- Defined complete result binding and exit validation while keeping adapter success distinct from workflow completion.
- Documented bounded conversion into worktree, generic-effect, and publication protocols, including safe `push_state_uncertain` recovery through a newly authorized adapter preflight rather than blind repetition.
- Added a contract that derives the schema inventory, independently pins the seven operations, checks structured authority and recovery sections, and verifies isolated nested-directory discovery with OpenCode 1.18.26.
- Preserved CLI, API, repository adapter, schema, Git, workflow, and publication behavior.

## Risks

- Skill instructions are not a runtime security boundary; later orchestration and installation work must enforce authority.
- Adapter evidence binds supplied ownership but cannot independently prove its freshness in Rails.
- Version 1 has no generic adapter observation command for unresolved commit, fetch, or rebase effects.
- Existing adapter integration tests exercise the application object rather than a complete executable-process contract; widening that coverage is outside this task.
