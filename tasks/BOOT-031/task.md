---
title: Verified Conditional Publication Push
task: BOOT-031
created: 2026-09-13
---

# BOOT-031: Verified Conditional Publication Push

## Goal

Add a safe `push` operation to `kos-repository` that conditionally publishes the exact reviewed candidate to the registered trusted remote and base ref and returns authenticated bounded remote observation after every attempted push.

## User Outcome

An orchestrator can invoke the sole Git mutation boundary to publish a prepared candidate without overwriting a moved base and can durably reconcile success, rejection, or an unknown push response from adapter-generated remote evidence.

## Context

BOOT-030 implemented durable publication preparation, ownership, recovery, and reconciliation without Git execution. The repository adapter already provides verified trusted fetch and rebase operations, but its closed version 1 contract has no push operation. Publication cannot progress safely until the adapter can enforce the expected remote OID and observe candidate reachability after transport uncertainty.

## Requirements

- BOOT-031-REQ-001: Add a closed version 1 `push` request and result contract binding the registered repository trust snapshot, publication identity and immutable parameters, current owner attempt, fencing token, and input-context digest.
- BOOT-031-REQ-002: Prove repository identity before lock creation, repeat validation under the common-directory adapter lock, and hold that lock through preflight observation, any push attempt, and post-push observation.
- BOOT-031-REQ-003: Validate the exact trusted remote, normalized URL, full base ref, local SHA-1 candidate commit, expected remote OID, publication ownership snapshot, and candidate ancestry before transport.
- BOOT-031-REQ-004: Fetch and observe the trusted base ref before mutation. Return success without another push when the candidate is already reachable, and return an unreachable observation without pushing when the observed tip differs from the expected OID.
- BOOT-031-REQ-005: Update only `<candidate-sha>:<configured-base-ref>` with an exact expected-old-OID compare-and-swap and an independently verified fast-forward relation. Never delete a ref or perform a non-fast-forward update.
- BOOT-031-REQ-006: After every attempted push, including rejection, timeout, or another unknown response, perform a bounded trusted fetch and return the observed tip, candidate reachability, UTC observation time, and canonical evidence digest when observation succeeds.
- BOOT-031-REQ-007: Treat a valid remote observation as adapter success regardless of the preceding push response. Return a closed retryable `unknown` result only when a push was attempted and the post-push remote state cannot be established.
- BOOT-031-REQ-008: Reject configured push URLs, receive-pack overrides, URL rewrites, executable transports, credential helpers, proxy and SSH overrides, and other configuration that can redirect or execute publication behavior outside the trusted boundary.
- BOOT-031-REQ-009: Keep output and diagnostics closed and safe. Never expose raw Git diagnostics, supplied paths, remote URLs, credentials, or environment values.
- BOOT-031-REQ-010: Preserve existing worktree, commit, fetch, rebase, CLI, persistence, and workflow contracts.

## Scope

- Repository adapter version 1 push request, success, failure, and unknown schemas.
- Conditional push implementation, trusted preflight and post-push observation, evidence generation, and application dispatch.
- Contract, real-Git integration, configuration safety, timeout, response-loss, retry, race, and lock coverage.
- Repository protocol specifications and focused user documentation.

## Non-Goals

- Mandatory-check execution inside `kos-repository`; the orchestrator verifies review and checks before invocation.
- Rails `publication.complete`, publication artifact registration, or transition to `completed`.
- Runtime skill or orchestrator implementation.
- New candidate generation after base movement.
- Live HTTPS or SSH authentication testing.

## Related Specifications And ADRs

- [Publication](../../docs/specs/publication.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Workflow Execution](../../docs/specs/workflow-execution.md)
- [Architecture Rules](../../docs/rules/architecture.md)
- [Testing Rules](../../docs/rules/testing.md)
- [ADR-0002: Recoverable Workflow Attempts](../../docs/decisions/0002-recoverable-workflow-attempts.md)
- [ADR-0004: Task Git Protocol](../../docs/decisions/0004-task-git-protocol.md)

## Task-Local Decisions

- BOOT-031-DEC-001: Publication authorization is an orchestrator-supplied, evidence-bound snapshot. The local adapter validates its internal consistency but does not query Rails to prove current lease or fencing ownership.
- BOOT-031-DEC-002: Exact remote compare-and-swap uses `--force-with-lease=<ref>:<expected-oid>` only after proving that the expected OID is an ancestor of the candidate. Although the Git option contains `force`, this combination cannot authorize a non-fast-forward update from the expected state.
- BOOT-031-DEC-003: Every invocation observes the remote before mutation. This makes retry after a lost response safe without requiring separate prior-fetch evidence in the push request.
- BOOT-031-DEC-004: A successful adapter result means that a trustworthy remote observation was obtained. Candidate reachability determines publication success at the application layer; an unreachable observation remains a successful adapter observation.
- BOOT-031-DEC-005: A missing or deleted base ref cannot satisfy the released publication reconciliation schema's required SHA-1 tip and is therefore reported as an uncertain observation rather than inventing an OID.
- BOOT-031-DEC-006: Mandatory checks and review authorization remain orchestration responsibilities because no executable check contract exists at the repository adapter boundary.

## Acceptance Criteria

- BOOT-031-AC-001: The closed adapter schema accepts only complete push snapshots and closed operation-specific success, failure, and unknown results.
- BOOT-031-AC-002: A local bare trusted remote is fast-forwarded from exactly the expected OID to the exact candidate, and the result proves candidate reachability.
- BOOT-031-AC-003: A moved base, invalid candidate ancestry, trust mismatch, ownership mismatch, or unsafe configuration never updates the remote.
- BOOT-031-AC-004: An already reachable candidate is observed idempotently without another mutation.
- BOOT-031-AC-005: A rejected or timed-out push followed by successful fetch returns the authoritative observation; inability to observe after an attempted push returns retryable `unknown`.
- BOOT-031-AC-006: Push changes no local ref, task branch, index, or worktree and cannot update tags or unrelated remote refs.
- BOOT-031-AC-007: Repository locking serializes validation, push, and observation for cooperating adapter processes, while the remote expected-OID condition prevents overwrite by an independent publisher.
- BOOT-031-AC-008: Evidence binds the complete repository and publication snapshots, candidate, target, observed tip, reachability, and observation time.
- BOOT-031-AC-009: Existing adapter and CLI contracts remain passing, and focused tests, `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-031 active externally.
2. Extend the closed repository adapter schema with push request, success, failure, and unknown documents.
3. Implement trusted preflight fetch, exact conditional push, post-push fetch, reachability verification, evidence generation, and safe uncertainty classification.
4. Add contract and real-Git integration coverage for success, retries, moved base, transport responses, post-push uncertainty, configuration isolation, locking, and concurrent remote movement.
5. Clarify orchestration versus adapter responsibilities in the repository protocol specifications and README.
6. Run focused tests, `mise run check`, and `git diff --check`; review the complete diff.
7. Record verification and result, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run `bundle exec rspec spec/contracts/repository_v1_contract_spec.rb`.
- Run `bundle exec rspec spec/integration/kos/repository/application_spec.rb`.
- Run publication and CLI contract regressions affected by shared publication result shapes.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-13:

- Repository adapter contract and real-Git integration coverage passed with 123 focused examples after the initial implementation and 124 examples after the final security hardening.
- Publication request and CLI contract regressions passed together with the adapter suite: 221 examples and no failures before final hardening.
- Final `mise run check` passed with 577 examples and no failures, 154 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Independent correctness and security reviews verified exact-old-OID behavior, unknown recovery, signing and Trace2 suppression, isolation from shared `FETCH_HEAD`, and rejection of direct, included, and worktree-scoped executable configuration. No high- or medium-severity findings remained within the approved adapter-only baseline.

## Implementation Result

- Added the closed version 1 `push` request, success, failure, and unknown adapter documents with publication ownership, fencing, candidate, trust target, observation, and evidence bindings.
- Implemented preflight trusted fetch plus exact-ref `ls-remote` observation, idempotent already-reachable handling, moved-base rejection without push, verified candidate ancestry, and exact expected-old-OID publication of only the configured base ref.
- Added mandatory post-push observation after successful, rejected, timed-out, or otherwise unknown responses. A trustworthy observation is returned as adapter success; an unavailable observation after push begins is a retryable `unknown` result.
- Hardened publication subprocesses against hooks, push signing, Trace2, credential and HTTP overrides, custom receive-pack and push URLs, URL rewrites, executable transports, config includes, and worktree-scoped configuration.
- Removed shared `FETCH_HEAD` from push evidence generation, preserved local refs, index, and worktrees, and bound canonical evidence to the complete trust and publication snapshots.
- Clarified that the orchestrator verifies approved review, mandatory checks, active ownership, and task state immediately before invoking the repository adapter.

## Risks

- Git cannot enforce a KOS fencing token. The adapter binds the supplied ownership snapshot into evidence, while exact expected remote OID acts as the external-system fence.
- A remote can move after the bounded observation; evidence proves the observed state at its timestamp, not permanent remote state.
- Real authenticated HTTPS and SSH transport behavior remains unverified in this task.
- Existing fetch semantics prove the observed commit object rather than the complete reachable object closure; inability to decide ancestry fails safely.
- The evidence digest is not a cryptographic signature. Version 1 trusts the lease-owning orchestrator to pass the direct adapter result to durable reconciliation; authenticating that local process channel would require a broader runtime and API contract.
