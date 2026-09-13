---
title: OpenCode Runtime Adapter Contract
task: BOOT-032
created: 2026-09-13
---

# BOOT-032: OpenCode Runtime Adapter Contract

## Goal

Define and automatically verify the first supported OpenCode runtime adapter contract before implementing canonical KOS skills.

## User Outcome

KOS has a proven way to discover project-local skills, invoke OpenCode non-interactively in an exact task worktree, launch and resume a workflow-step subagent, and complete a synchronous typed repository-effect round trip before accepting the subagent's final result manifest.

## Context

OpenCode 1.18.26 provides non-interactive JSON event output, project-local skill discovery, and foreground Task tool calls that return an opaque child session identifier and can resume that session. KOS specifications require these capabilities but do not define the exact adapter transport, supported runtime version, or executable compatibility checks.

## Requirements

- BOOT-032-REQ-001: Support exactly OpenCode 1.18.26 until another version passes the complete adapter contract.
- BOOT-032-REQ-002: Define `.opencode/skills/<name>/SKILL.md` as the first runtime target and prove project-local skill discovery from a nested directory within the Git worktree.
- BOOT-032-REQ-003: Invoke OpenCode non-interactively with JSON events and an explicit task-worktree working directory; the parent and child sessions must use that exact worktree.
- BOOT-032-REQ-004: Launch workflow steps through a foreground Task tool call and treat the returned child session identifier as opaque runtime state.
- BOOT-032-REQ-005: Resume only that same child session when returning a typed repository-effect result.
- BOOT-032-REQ-006: Define a closed workflow-step turn transport that carries either the existing version 1 effect request or the final result manifest, never prose or mixed output.
- BOOT-032-REQ-007: Require the orchestrator to validate every turn, identity, digest, operation, and ordering invariant before acting on model output or returning an effect result.
- BOOT-032-REQ-008: Verify discovery, invocation, child launch, cwd, and effect round-trip against the real pinned OpenCode executable without user configuration, credentials, or an external AI provider.
- BOOT-032-REQ-009: Preserve the existing CLI, repository adapter, workflow, persistence, and retrospective contracts.

## Scope

- OpenCode runtime transport and capability JSON Schema.
- An ADR for the initial OpenCode adapter and foreground child-session continuation mechanism.
- Focused runtime, workflow, initialization, and user documentation updates.
- Project toolchain pin for OpenCode 1.18.26.
- Test-only OpenCode skill, agent, plugin, and deterministic local model fixtures.
- Contract and real-process integration coverage.

## Non-Goals

- Production implementations of `kos-cli`, `kos-orchestrate`, `kos-workflow-step`, or other canonical skills.
- Runtime installation, copy manifests, staging, or drift detection.
- Retrospective hooks or two-phase retrospective result delivery.
- Execution of real KOS state mutations or Git repository effects.
- Claude Code, another runtime target, or another OpenCode version.
- Network-backed provider tests.

## Related Specifications And ADRs

- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Initialization](../../docs/specs/initialization.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Testing Rules](../../docs/rules/testing.md)

## Task-Local Decisions

- BOOT-032-DEC-001: The first supported range is the singleton version 1.18.26. Compatibility is widened only after the same executable contract passes.
- BOOT-032-DEC-002: A workflow-step turn is exactly one JSON document selected from the existing effect-request and result-manifest contracts; the runtime wrapper does not duplicate their payload fields.
- BOOT-032-DEC-003: The orchestrator retains the opaque Task tool child session identifier and resumes that child after a typed effect result. OpenCode session identifiers are runtime routing data, not KOS workflow identity.
- BOOT-032-DEC-004: A deterministic loopback fake model verifies the real runtime process and tool loop without making provider behavior or credentials part of the project test suite.

## Acceptance Criteria

- BOOT-032-AC-001: The closed runtime schema accepts only a complete capability report and an effect request or final manifest as a workflow-step turn.
- BOOT-032-AC-002: A fixture skill is discovered from a nested directory inside an isolated Git worktree.
- BOOT-032-AC-003: `opencode run --format json --dir` completes without interaction and emits parseable JSON events.
- BOOT-032-AC-004: A configured workflow-step agent runs as a child of the orchestrator and both sessions observe the exact task-worktree cwd.
- BOOT-032-AC-005: The child returns a valid effect request, receives a valid effect result in the same runtime session, and then returns a valid final result manifest.
- BOOT-032-AC-006: Prose, mixed output, malformed documents, mismatched identities or digests, an unexpected turn, and a changed child session are rejected.
- BOOT-032-AC-007: Tests use isolated home, config, data, cache, and state paths and only a loopback fake provider.
- BOOT-032-AC-008: Focused tests, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-032 active externally.
2. Add the OpenCode runtime schema and architecture decision.
3. Align runtime, workflow, initialization, and user documentation with the exact adapter mechanics and trust boundary.
4. Pin OpenCode 1.18.26 in the project toolchain.
5. Add isolated runtime fixtures and a deterministic loopback model harness.
6. Cover skill discovery, non-interactive JSON invocation, parent/child cwd, child continuation, typed effect transport, and invalid turns.
7. Run focused tests, `mise run check`, and `git diff --check`; review the complete diff.
8. Record verification and result, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run the focused OpenCode runtime contract specs while iterating.
- Run the affected schema contract specs.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-13:

- `bundle exec rspec spec/contracts/open_code_runtime_adapter_contract_spec.rb` passed with 6 examples and no failures in about 4.2 seconds.
- The OpenCode and CLI contract suites passed together with 93 examples and no failures.
- Final `mise run check` passed with 583 examples and no failures, 157 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent correctness and security reviews verified capability completeness, strict raw transport parsing, session rebinding prevention, exact effect request digest and intent binding, failure-result delivery, cwd evidence, skill execution, process termination, and deterministic dependency isolation. No high- or medium-severity findings remained.

## Implementation Result

- Added the closed OpenCode version 1 capability, workflow-step completion, and effect-delivery documents while reusing the existing CLI effect and manifest contracts.
- Added an executable transport state machine that parses completed Task events, cross-checks wrapper and metadata session IDs, validates schemas and workflow identities, enforces turn ordering, and binds effect intent, request digest, operation, and overlapping target fields.
- Defined OpenCode 1.18.26 as the singleton supported runtime version and recorded foreground Task continuation plus a per-parent session guard as ADR-0008.
- Added isolated fixture skills and agents, a session-guard plugin, and a deterministic loopback OpenAI-compatible provider that drive the real OpenCode executable through discovery, non-interactive invocation, parent and child cwd observation, effect delivery, final result, and rejected session rebinding.
- Isolated home, configuration, data, cache, state, provider credentials, and npm dependency state so compatibility checks neither read personal OpenCode state nor depend on an external AI provider.
- Pinned OpenCode 1.18.26 in the project toolchain and aligned runtime, workflow, initialization, and user documentation.

## Risks

- The OpenCode Task tool is not a KOS security boundary. The orchestrator must retain and use only the child identifier returned by its own foreground invocation.
- Model output is untrusted even in structured-looking text and must pass strict schema and identity validation.
- Exact version support is intentionally narrow and requires explicit revalidation after OpenCode upgrades.
- Retrospective transport remains unverified until its separate runtime task.
- Runtime installation and production canonical skills must materialize the specified session guard; this task proves the mechanism with test fixtures but does not ship installed copies.
