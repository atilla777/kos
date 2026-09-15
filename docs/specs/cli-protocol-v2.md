---
title: KOS CLI Protocol Version 2
status: active
---

# KOS CLI Protocol Version 2

## Boundary And Coexistence

Version 2 is a minimal additive protocol for durable publication preflight, immutable publication-result handoff, and the base-movement recovery mutations that require new atomic request shapes. It coexists with immutable version 1 and does not duplicate unrelated version 1 commands. A client uses each command through the version that catalogs it; one request or response never mixes document versions.

Version 2 uses JSON Schema draft 2020-12. Every version 2 document contains `"schema_version": "2"`, every object is closed, every schema has a unique `$id` below `https://kos.local/schemas/cli/v2/`, and every `$ref` resolves within `schemas/cli/v2/` without network access. Names, UUIDs, timestamps, SHA-256 digests, full SHA-1 Git OIDs, idempotency, JSON output, authentication, retry, and repository-authorization rules retain the version 1 conventions unless this document narrows them.

The normative schemas are:

| File | Contract |
| --- | --- |
| `schemas/cli/v2/common.json` | Version, identifiers, Git values, and leased preconditions |
| `schemas/cli/v2/resources.json` | Publication-preflight, publication, and publication-result resources |
| `schemas/cli/v2/envelopes.json` | Success, failure, and closed safe errors |
| `schemas/cli/v2/commands.json` | The eight request and result documents |
| `schemas/cli/v2/catalog.json` | Exact CLI/API bindings, statuses, and preconditions |

## Commands

Every command is repository-scoped and requires `--repository <repository-id> --json`. Mutations also require `--input <path|-> --idempotency-key <key>` and carry leased preconditions in their body.

| Identifier | CLI syntax | HTTP binding | Success |
| --- | --- | --- | --- |
| `publication_preflight.get` | `kos publication-preflight get --preflight UUID` | `GET /api/v2/repositories/{repository_id}/publication-preflights/{preflight_id}` | `200` preflight |
| `publication_preflight.prepare` | `kos publication-preflight prepare` | `POST /api/v2/repositories/{repository_id}/tasks/{task_number}/publication-preflights` | `201` prepared preflight |
| `publication_preflight.reconcile` | `kos publication-preflight reconcile` | `POST /api/v2/repositories/{repository_id}/publication-preflights/{preflight_id}/reconcile` | `200` reconciled or unknown preflight |
| `publication.prepare_observed` | `kos publication prepare-observed` | `POST /api/v2/repositories/{repository_id}/publication-preflights/{preflight_id}/publication` | `201` prepared publication |
| `publication_result.get` | `kos publication-result get --publication UUID` | `GET /api/v2/repositories/{repository_id}/publications/{publication_id}/result` | `200` publication result |
| `publication_result.record` | `kos publication-result record` | `POST /api/v2/repositories/{repository_id}/publications/{publication_id}/result` | `201` publication result |
| `publication.recover_base_moved` | `kos publication recover-base-moved` | `POST /api/v2/repositories/{repository_id}/publications/{publication_id}/recover-base-moved` | `200` recovery transition |
| `effect.reconcile_rebase` | `kos effect reconcile-rebase` | `POST /api/v2/repositories/{repository_id}/repository-effects/{effect_id}/reconcile-rebase` | `200` reconciled rebase and worktree |

Read path values come from validated CLI options. Mutation path values come from the validated body. The API rejects any path/body/repository mismatch as `malformed_input`.

## Durable Preflight

`publication_preflight.prepare` accepts the task number, exact reviewed candidate SHA, trusted remote, full base ref, and leased preconditions. The server revalidates repository scope, task lock, publication workflow status, active lease and fencing token, current candidate generation, approved independent review for that candidate, and equality with the repository's trusted target. It then durably records intent before any remote observation. Preparing concurrently or replaying idempotently produces at most one active matching preflight.

Only `kos-repository` observes the remote. It revalidates repository identity, trust, and Git configuration, fetches exactly the trusted base ref with bounded output, and returns the observed OID, observation time, and canonical evidence digest. The server verifies all canonical repository, preflight, owner, fencing, candidate, remote, ref, OID, and timestamp bindings before recording a concrete observation.

`publication_preflight.reconcile` accepts either the concrete `observed_remote_oid`, `observed_at`, and `evidence_digest`, or one closed `unknown` safe error. Concrete evidence moves the resource to `reconciled`. Unknown or lost observation moves it to unresolved `unknown`; after lease recovery a new attempt adopts the same intent and reconciles it from observation rather than blindly repeating the external effect. A replacement unknown may update only the current safe error and owner attribution. A consumed preflight is immutable.

The resource states are:

| State | Meaning |
| --- | --- |
| `prepared` | Durable intent exists; no verified observation is recorded |
| `unknown` | Observation outcome is unresolved and must be recovered without blind retry |
| `reconciled` | Canonical evidence fixes the observed remote OID |
| `consumed` | Exactly one publication was prepared from that observation |

`publication.prepare_observed` accepts only `preflight_id` and leased preconditions. It revalidates current ownership, task and candidate generation, approved review, and trusted target, then atomically consumes the reconciled preflight and creates the existing publication-shaped version 2 resource. The publication's `expected_remote_oid` is copied from the preflight's `observed_remote_oid`; no caller OID is accepted. Concurrent consumption creates at most one publication, and idempotent replay returns that same result.

The push adapter still performs its immediate trusted-remote preflight and exact-old-OID fast-forward checks. A durable observation does not assert that the remote remains unchanged after it was recorded.

## Publication Result Handoff

`publication_result.record` accepts the publication identifier, the exact schema-valid succeeded child result manifest, and leased preconditions. The path and body publication identifiers must agree. Only the original live attempt named by the manifest and its frozen input-context digest may record it. The server revalidates the repository, task lock and candidate generation, active lease and fencing token, approved independent review, passed checks, trusted target, reconciled publication, manifest identity and outcome, and reachable push observation. It reconstructs the complete canonical push-evidence input from durable state and recomputes its digest rather than trusting a caller-supplied digest. It then atomically creates one immutable result containing the exact manifest and snapshots all validated identities and evidence.

One publication has at most one result. Same-key replay returns the recorded result, while a concurrent or conflicting manifest is rejected and cannot alter cleanup state. The result becomes usable only after this transaction commits.

`publication_result.get` is a repository-scoped read by publication identifier. It returns the immutable result, including the original producer attempt, frozen input-context digest, exact manifest, candidate and trusted target, passed-check and approved-review bindings, and canonical reachable push-evidence snapshot. It does not require or reveal the producer's record idempotency key. A replacement publication attempt may retrieve it and, with its own current leased preconditions on the existing cleanup operation, authorize only the worktree release protocol. Retrieval does not transfer result ownership, authorize another push, submit the manifest, register an artifact, complete an attempt, invoke `publication.complete`, or move the task to its terminal status.

The application rejects publication release preparation without this result, and the database independently prevents the publication reservation from entering `release_pending` while no result exists. Existing release requests and responses remain version 1 documents; this version 2 addition changes their server-side publication precondition, not their schemas. Clean matching recovery may continue at every durable release boundary. Dirty or mismatched observations remain pending and cannot be converted into release authorization by the result.

## Base-Movement Recovery

`publication.recover_base_moved` accepts the superseded publication identifier and leased preconditions. The server requires the task's pinned workflow to declare the exact publication recovery edge, revalidates the current candidate and durable moved-base observation, and accepts either the original live publication attempt or a replacement publication attempt claimed after interruption. It atomically records the successful no-artifact recovery transition, releases the attempt lease, and moves the task to the declared base-synchronization status. Idempotent replay returns the recorded transition; concurrent or stale requests cannot take it twice.

`effect.reconcile_rebase` is the base-synchronization success boundary. It accepts a prepared rebase identifier, the returned HEAD, rebase evidence digest, canonical clean-worktree observation digest, and leased preconditions. The server verifies canonical rebase evidence against the durable intent, successful trusted fetch, superseded publication base, reservation, and result; verifies that the worktree observation binds the same reservation, fencing token, frozen context, and returned HEAD; and atomically marks the rebase succeeded while updating the confirmed reservation's clean HEAD. A crash before this mutation leaves the generic effect unresolved and fail-closed. A crash after it leaves both records durably consistent; after lease reconciliation, a replacement owner repeats the trusted fetch and the adapter's verified no-op rebase before recording its own owner-bound pair and completing the step.

## Contract Verification

Contract tests validate every schema against its metaschema, resolve every reference locally, cover all command requests and results, enforce repository-scoped `/api/v2` catalog entries and leased mutation preconditions, exercise all preflight states and publication-result interruption boundaries, and reject caller-supplied OIDs, incomplete concrete observations, noncanonical or unreachable push evidence, mismatched producer or context, non-succeeded manifests, open unknown errors, mixed versions, and extra properties. Persistence and concurrency coverage proves one immutable result per publication and proves that application bypass cannot move a publication reservation to `release_pending` before that result exists. Version 1 schemas and published workflows remain byte-for-byte unchanged.
