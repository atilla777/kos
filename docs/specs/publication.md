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
6. Registers the artifact and advances workflow status through the CLI in one transaction.

Only the reviewed candidate may be published to the trusted remote and base ref. Force-push is prohibited.

## Recovery And Base Movement

If push outcome is unknown, such as a connection loss after sending data, publication fetches the remote before attempting another push. Every adapter invocation performs this preflight observation: it returns without another push when the candidate is already reachable and does not push when the observed tip differs from the prepared expected OID. A retry is allowed only when the candidate is not reachable and the base ref still equals that OID. The same idempotency key returns the already recorded outcome.

If another task moved the base branch, KOS rejects the push. The task must synchronize with the current base, produce a new candidate SHA, repeat required checks and independent review, and then publish the new generation. Evidence for the old candidate does not satisfy the new candidate.

The trusted remote name, normalized URL, and full base ref are chosen once during initialization with human confirmation and stored in KOS state. Automatic `main` or `master` detection is allowed only during initialization and still requires explicit human confirmation.

Publication uses the reservation, lease, fencing, and adapter boundaries in [Repository Isolation](repository-isolation.md). [ADR-0004](../decisions/0004-task-git-protocol.md) records the protocol rationale.
