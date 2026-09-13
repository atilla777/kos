---
title: Canonical KOS CLI Skill
task: BOOT-033
created: 2026-09-13
---

# BOOT-033: Canonical KOS CLI Skill

## Goal

Add the canonical `kos-cli` skill that teaches runtime agents to use the non-interactive Ruby CLI as the only KOS state interface, validate versioned JSON results, and handle stable failures without blind mutation retries.

## User Outcome

An agent can safely invoke the currently implemented `kos` commands, accept only validated protocol version 1 results, and choose reread or reconciliation paths after conflicts, lease loss, and uncertain mutation outcomes.

## Context

The CLI already validates command bodies and API responses against the version 1 schemas, emits one JSON document, uses stable exit categories, and performs bounded retries only for transient failures. The schema catalog includes five commands that are not yet implemented by the CLI, so this skill describes only executable commands and does not widen the implementation scope.

## Requirements

- BOOT-033-REQ-001: Add `skills/kos-cli/SKILL.md` as the sole canonical source with OpenCode-compatible `name` and `description` frontmatter; do not add `skills/index.md`.
- BOOT-033-REQ-002: Require all agent-facing KOS state access to use the installed non-interactive `kos` command and prohibit direct REST, SQLite, Rails model, Rails runner, and manual state access.
- BOOT-033-REQ-003: Keep state operations separate from repository operations; the skill must not perform mutating Git commands or replace `kos-repository`.
- BOOT-033-REQ-004: Do not widen actor authority. Attempt-owned mutations require the lease-owning orchestrator and authoritative attempt, lock-version, and fencing-token values; workflow-step subagents do not use the state CLI.
- BOOT-033-REQ-005: Document protocol version 1 invocation, global and repository scope, `--json`, mutation input, idempotency keys, environment-only authentication, and non-interactive execution.
- BOOT-033-REQ-006: Require validation of the single JSON result's schema version, command, request ID, success or error branch, and process exit before consuming data.
- BOOT-033-REQ-007: Branch on stable error category, code, and retryability rather than human-readable messages or stderr.
- BOOT-033-REQ-008: Prohibit blind mutation retries. Conflicts and lease loss require authoritative rereads or recovery; unfinished and unknown durable effects require resource inspection and reconciliation; a transport failure never justifies a new idempotency key for the same intent.
- BOOT-033-REQ-009: State that the CLI already performs at most three transient attempts and prohibit an unbounded retry loop above it.
- BOOT-033-REQ-010: Use only fresh authoritative identifiers and preconditions; never infer task state, UUIDs, lock versions, fencing tokens, or transitions.
- BOOT-033-REQ-011: Describe only commands implemented by the current CLI and do not present catalog-only commands as available.
- BOOT-033-REQ-012: Keep the skill independent of a KOS source checkout and rely on the installed CLI for full request and response schema validation.
- BOOT-033-REQ-013: Add deterministic contract coverage for frontmatter, safety guidance, implemented command inventory, and OpenCode 1.18.26 discovery.
- BOOT-033-REQ-014: Preserve CLI, API, schema, retry, workflow, and repository-adapter behavior.

## Scope

- The canonical `kos-cli` skill.
- A focused static and pinned-OpenCode discovery contract.
- This task record and external bootstrap plan updates.

## Non-Goals

- Implementing `repository.register`, runtime configuration, `artifact.register`, or `publication.complete`.
- Changing CLI or API commands, JSON Schema version 1, stable errors, or retry behavior.
- Implementing orchestration, workflow-step execution, repository, initialization, installation, or retrospective skills.
- Runtime permission enforcement, installation manifests, drift detection, or automatic materialization.
- Git operations, a complete quick-fix workflow, Claude support, or model-compliance testing.

## Related Specifications And ADRs

- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Initialization](../../docs/specs/initialization.md)
- [ADR-0001](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0004](../../docs/decisions/0004-task-git-protocol.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)

## Task-Local Decisions

- BOOT-033-DEC-001: The canonical skill uses the installed `kos` executable; repository-local `bin/kos` remains a development entrypoint.
- BOOT-033-DEC-002: The CLI performs full JSON Schema validation. The skill independently checks the envelope version, command, branch, and exit status before using the result.
- BOOT-033-DEC-003: The skill lists only currently implemented commands and identifies catalog-only operations as unavailable rather than implying support.
- BOOT-033-DEC-004: After the CLI exhausts transient retries for a mutation, the outcome is potentially unknown; recovery starts with authoritative read or reconciliation and preserves the original request and idempotency key.

## Acceptance Criteria

- BOOT-033-AC-001: `skills/kos-cli/SKILL.md` exists with valid identifying frontmatter and no canonical skill index is added.
- BOOT-033-AC-002: A test-time installed copy is discovered by pinned OpenCode 1.18.26 from a nested worktree directory.
- BOOT-033-AC-003: The skill establishes the CLI-only state boundary, actor authority, and separation from Git mutation.
- BOOT-033-AC-004: The skill provides correct read and mutation invocation forms with JSON output, repository scope, input, and idempotency requirements.
- BOOT-033-AC-005: The skill requires protocol version, command, result branch, and exit validation before data is used.
- BOOT-033-AC-006: All stable error categories fail closed; only transient errors are retryable, and the skill directs conflicts, lease loss, and unknown effects to reread or reconciliation paths.
- BOOT-033-AC-007: A transient mutation failure never causes a new idempotency key for the same logical intent.
- BOOT-033-AC-008: The skill does not present an unimplemented catalog command as available.
- BOOT-033-AC-009: Focused contracts, affected CLI and runtime contracts, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-033 active externally.
2. Add the self-contained canonical `kos-cli` skill with boundaries, invocation rules, result validation, command inventory, and stable error recovery.
3. Add static contract checks and install the canonical file into an isolated OpenCode fixture for real pinned-runtime discovery.
4. Run focused CLI and runtime contracts, then the complete project checks and whitespace validation.
5. Record verification and implementation results, update the external plan, review the diff, commit only task files, and push normally to `main`.

## Verification

- Run the focused `kos-cli` skill contract while iterating.
- Run the affected OpenCode runtime, CLI schema, and CLI process contracts.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-13:

- `bundle exec rspec spec/contracts/kos_cli_skill_contract_spec.rb` passed with 8 examples and no failures.
- The focused skill, OpenCode runtime, CLI schema, and CLI process contracts passed together before the final contract strengthening; the final full suite subsumed those checks.
- Final `mise run check` passed with 591 examples and no failures, 158 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent safety and test reviews verified trusted endpoint handling, exact same-key recovery after a lost creation response, separation from external-effect replay, the pinned OpenCode version and bounded process execution, exact command scope and mutation classification, and stable exit/category/action bindings. No high- or medium-severity findings remained.

## Implementation Result

- Added the first production canonical skill at `skills/kos-cli/SKILL.md` with the installed CLI invocation contract, actor and state boundaries, current command inventory, versioned result validation, stable error actions, and idempotent recovery rules.
- Explicitly protects the bearer token by treating `KOS_API_URL` as trusted installation configuration and prohibiting model- or task-controlled replacement.
- Distinguishes safe exact replay of an idempotent state mutation from prohibited blind repetition of an unknown Git or other external effect.
- Added a contract derived from the actual CLI parser that rejects missing, extra, duplicated, or misclassified commands and verifies frontmatter, unavailable commands, safety guidance, stable exits, OpenCode 1.18.26, nested-directory discovery, isolated runtime state, and bounded subprocess cleanup.
- Preserved the existing CLI, API, schema, workflow, and repository-adapter behavior.

## Risks

- Skill instructions are not a security boundary; runtime agent permissions and orchestrator validation must enforce authority in later tasks.
- Canonical skills are not automatically installed until `kos-initialize` implements materialization.
- The protocol catalog is ahead of implementation for five commands; the skill must not conceal that gap or expand it in this task.
- Static contract tests protect the required operational statements and structured tables but cannot prove that an arbitrary model will obey the skill or detect every possible contradictory prose edit.
