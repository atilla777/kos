---
title: KOS Publication
status: active
---

# KOS Publication

## Candidate Contract

Before review, a workflow fixes a candidate commit SHA containing all required code, test, and documentation changes. That immutable commit is the object reviewed. Every task commit carries its repository-specific public number in a trailer such as `KOS-Task: KOS-000123`; a task-number prefix in the subject is allowed but not required.

## Publication Protocol

After approval of that candidate, publication:

1. Records durable intent containing candidate SHA, configured remote, and full base ref.
2. The orchestrator runs mandatory checks in a clean checkout of the exact candidate SHA.
3. The orchestrator confirms that approved review evidence refers to that SHA and verifies the active attempt, task version, and prepared publication immediately before invoking `kos-repository`.
4. `kos-repository` observes the trusted remote and pushes `<candidate-sha>:<configured-base-ref>` only when the observed base ref equals the prepared expected OID and that OID is an ancestor of the candidate.
5. After every attempted push, including an unknown response, `kos-repository` fetches the trusted remote and returns bounded evidence containing the observed remote tip and candidate reachability.
6. After reconciling canonical evidence that the candidate is reachable, the producing attempt records its immutable publication result before requesting worktree cleanup.
7. A later completion operation registers the artifact and advances workflow status through the CLI in one transaction.

Only the reviewed candidate may be published to the trusted remote and base ref. Force-push is prohibited.

For new publication attempts, the additive version 2 path obtains the expected remote OID through a durable publication preflight before creating the publication intent. The orchestrator first prepares a preflight bound to the current reviewed candidate and trusted target, then asks only `kos-repository` to observe that target. Concrete reconciliation requires server verification of canonical adapter evidence containing `observed_remote_oid`, `observed_at`, and `evidence_digest`. An unknown result remains unresolved and is adopted and reconciled after interruption without a blind repeat.

Observed preparation accepts the reconciled preflight identifier and leased preconditions, never a caller-supplied OID. It atomically consumes that preflight and creates the existing publication-shaped resource with `expected_remote_oid` copied from the verified observation. Concurrent preparation, reconciliation, and consumption preserve idempotency, lock, lease, and fencing semantics and produce at most one active result. The exact machine surface is defined by [CLI Protocol Version 2](cli-protocol-v2.md), and [ADR-0011](../decisions/0011-minimal-cli-v2-coexistence.md) records why it coexists with immutable version 1.

## Durable Publication Result

A `PublicationResult` is separate from the mutable publication intent, workflow attempt, and eventual `TaskArtifact`. At most one exists for a publication. It immutably preserves the exact schema-valid succeeded child result manifest; its original producing attempt and frozen input-context digest; and a snapshot of the repository, task, publication, reviewed candidate generation, trusted remote and full base ref, approved review, passed candidate checks, and canonical push observation that proves the candidate reachable. The server reconstructs and verifies the canonical push evidence and its digest from the complete trusted publication and adapter observation snapshot; a caller-supplied digest alone is never evidence.

Only the live lease-owning attempt that produced the manifest may record the result. Recording revalidates repository scope, task lock and generation, lease and fencing token, frozen context, manifest identities and `succeeded` outcome, approved review, passed checks, trusted target, publication ownership, and reachable canonical push evidence in one transaction. Idempotent replay returns the same immutable result, and competing or different results are rejected.

The recovery guarantee begins only after that recording transaction commits. A replacement publication attempt may retrieve the result without the producer's idempotency key and may use its own current lease and fencing token only to authorize conservative worktree cleanup. It does not become the producer, rewrite the manifest or context, submit another child result, repeat the push, or use the result as authorization for publication completion.

The publication worktree cannot enter `release_pending` until its publication result exists. Application policy enforces the complete authorization and the database independently prevents the state change when no result is linked to that publication. After recording, cleanup retains the existing clean-observation, ownership, locking, and two-phase release rules; dirty or mismatched state remains pending for explicit resolution.

## Recovery And Base Movement

If push outcome is unknown, such as a connection loss after sending data, publication fetches the remote before attempting another push. Every push adapter invocation performs its own immediate preflight observation, independently of the durable preparation preflight: it returns without another push when the candidate is already reachable and does not push when the observed tip differs from the prepared expected OID. A retry is allowed only when the candidate is not reachable and the base ref still equals that OID. The same idempotency key returns the already recorded outcome.

If another task moved the base branch, KOS rejects the push. The task must synchronize with the current base, produce a new candidate SHA, repeat required checks and independent review, and then publish the new generation. Evidence for the old candidate does not satisfy the new candidate.

For workflow versions that declare base-movement recovery, a specialized idempotent operation may take that exact recovery edge only after revalidating the superseded publication, current candidate, active leased attempt, and pinned transition. It closes the publication attempt without fabricating publication evidence. The recovery status obtains the current base through a trusted fetch, performs one verified rebase of the frozen task HEAD, synchronizes the resulting clean HEAD into the durable reservation, and accepts it as a new candidate only with fresh passed checks. Conflict, failure, unknown effect state, an unchanged SHA, or stale evidence leaves the task in recovery. Published workflow versions without this edge remain fail-closed.

The trusted remote name, normalized URL, and full base ref are chosen once during initialization with human confirmation and stored in KOS state. Automatic `main` or `master` detection is allowed only during initialization and still requires explicit human confirmation.

Publication uses the reservation, lease, fencing, and adapter boundaries in [Repository Isolation](repository-isolation.md). [ADR-0004](../decisions/0004-task-git-protocol.md) records the protocol rationale.

[ADR-0013](../decisions/0013-immutable-publication-result-handoff.md) records why the successful child result is an immutable cross-attempt handoff established before cleanup.
