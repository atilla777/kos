---
title: Verified Trusted Fetch
task: BOOT-028
created: 2026-09-12
---

# BOOT-028: Verified Trusted Fetch

## Goal

Implement a verified `fetch` operation in `kos-repository` that fetches only the registered trusted base ref and returns a typed observed commit OID with canonical evidence.

## User Outcome

An orchestrator can ask the local repository adapter to fetch the registered base branch without allowing the request or repository configuration to redirect authority or modify arbitrary refs.

## Context

BOOT-027 implemented the durable REST and CLI lifecycle for generic repository effects without executing Git. The local repository adapter currently executes worktree and commit effects but has no fetch contract or implementation.

## Requirements

- BOOT-028-REQ-001: Add closed version 1 adapter request, success, and failure documents for fetch.
- BOOT-028-REQ-002: Bind the request and evidence to the registered repository and generic-effect identity, current owner attempt, fencing token, and canonical effect-request digest without querying Rails.
- BOOT-028-REQ-003: Accept only the exact registered trusted remote and registered base ref, require the configured remote's single effective URL to equal the registered normalized `https`, `ssh`, `git`, or `file` URL, reject passwords, queries, fragments, and encoded userinfo separators, and require an absolute nonempty path for `file` URLs without prohibiting their host authority.
- BOOT-028-REQ-004: Validate canonical Git common-directory identity, the requested ref, and SHA-1 object format before fetching.
- BOOT-028-REQ-005: Prove repository common-directory identity before creating its lock, then serialize complete repeated validation and fetch execution with other adapter mutations under that registered common-directory lock.
- BOOT-028-REQ-006: Fetch exactly one source ref with tags, pruning, submodules, auto-maintenance, configured refmaps, bundle URIs, HTTP redirects and alternate endpoints, promisor and partial-clone authority, URL redirection, and repository-configured executable transport overrides disabled.
- BOOT-028-REQ-007: Do not update local, task, remote-tracking, or tag refs; use only the bounded `FETCH_HEAD` result and object database changes made by Git.
- BOOT-028-REQ-008: Return success only when `FETCH_HEAD` unambiguously identifies a commit object available in the local object database, without claiming complete local closure of all reachable objects, and return canonical SHA-256 evidence binding the trusted request and observation.
- BOOT-028-REQ-009: Return only closed safe errors without raw Git diagnostics, supplied paths, remote URLs, or credentials.

## Scope

- Repository-adapter schema, dispatch, fetch implementation, and minimal shared repository-operation primitives.
- Contract and real-Git integration coverage using controlled local remotes.
- Focused repository-isolation specification and README updates.

## Non-Goals

- Rails persistence, REST or CLI workflow schema, or generic-effect lifecycle changes.
- Runtime skill or orchestrator integration.
- Rebase, push, or publication-specific post-push observation.
- Credential provisioning or live network tests.
- A persistent history of remote observations.

## Related Specifications And ADRs

- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)
- [ADR-0005: Central Persistence And Repository Registration](../../docs/decisions/0005-central-persistence-and-registration.md)

## Task-Local Decisions

- BOOT-028-DEC-001: Version 1 fetch authority is restricted to the exact registered base ref rather than every syntactically valid workflow `refs/*` value.
- BOOT-028-DEC-002: Fetch has no worktree reservation, but its adapter request carries the complete durable effect request and its verified digest plus the current owner and fencing snapshot so evidence cannot be confused across attempts. The adapter schema-validates and evidence-binds ownership but does not query Rails to establish snapshot freshness.
- BOOT-028-DEC-003: Fetch supplies no destination refspec. `FETCH_HEAD` is its bounded immediate observation; durable orchestration and unknown-result recovery remain separate integration work.
- BOOT-028-DEC-004: Generic transport failure is retryable because raw Git diagnostics are not parsed into the public contract. Trust and configuration mismatches are nonretryable.

## Acceptance Criteria

- BOOT-028-AC-001: Fetching the registered base ref from a controlled trusted remote returns its exact commit OID and schema-valid evidence.
- BOOT-028-AC-002: Repository binding, remote, URL, ref, and durable request-digest mismatches fail safely before fetch; effect identity, current owner, and fencing snapshots are closed, schema-valid, and evidence-bound.
- BOOT-028-AC-003: Fetch changes no Git refs, tags, task branches, worktrees, or index.
- BOOT-028-AC-004: Repository configuration cannot redirect the URL or select an executable transport or upload-pack override.
- BOOT-028-AC-005: Failure output is closed and contains no raw diagnostics, paths, URLs, or credentials.
- BOOT-028-AC-006: Fetch is serialized with existing adapter mutations and existing worktree and commit behavior remains covered.
- BOOT-028-AC-007: Focused tests, `mise run check`, and `git diff --check` pass before commit and normal push to `main`.

## Implementation Plan

1. Record this approved baseline and mark BOOT-028 active externally.
2. Extend the adapter schema with closed fetch documents and errors.
3. Add the minimal shared repository identity and lock boundary needed by fetch.
4. Implement explicit dispatch and verified single-ref fetch.
5. Add contract and integration coverage and update applicable documentation.
6. Run focused checks, `mise run check`, and `git diff --check`.
7. Review the diff, record results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run repository adapter contract and integration specs while iterating.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

Completed verification on 2026-09-12:

- Focused repository adapter contract and real-Git integration specs passed with 93 examples and no failures.
- Final `mise run check` passed with 520 examples and no failures, 143 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent security reviews identified and verified fixes for effect-request digest authenticity, executable transport overrides, HTTP and bundle redirection, pre-lock path mutation, trusted URL validation, and promisor or partial-clone alternate authority.

## Implementation Result

- Added a closed fetch adapter request carrying the registered trust snapshot, complete durable fetch request and verified canonical digest, repository effect identity, current owner attempt, and fencing token.
- Implemented exact trusted-remote and base-ref validation, canonical repository identity checks before and under the common adapter lock, and strict supported URL validation.
- Added a source-only fetch that disables configured refmaps, tags, pruning, submodules, maintenance, shallow updates, bundle and HTTP redirection, credential helpers, executable transport overrides, and promisor or partial-clone authority.
- Verified the single bounded `FETCH_HEAD` entry against the requested branch and a locally available commit object without updating any Git ref.
- Returned a typed observed OID and canonical evidence with closed safe fetch errors.
- Covered request/result contracts, trust and digest mismatches, URL and configuration attacks, side-effect containment, bounded observations, safe failures, and lock serialization with controlled real Git repositories.
- Documented the adapter contract while retaining Rails effects, runtime orchestration, rebase, push, and publication observation as separate boundaries.

## Risks

- Controlled tests do not prove real HTTPS or SSH authentication behavior.
- `FETCH_HEAD` is protected from concurrent KOS operations by the adapter lock, but an unrelated Git process does not honor that lock; the adapter verifies its observation immediately before returning.
- Fetch success verifies the observed commit object locally but does not prove that every object reachable from that commit is present.
- The shared CLI `remote_url` schema still permits plain HTTP despite the central-persistence specification; changing that existing CLI contract is outside this adapter task.
