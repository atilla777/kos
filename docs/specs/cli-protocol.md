---
title: KOS CLI Protocol Version 1
status: active
---

# KOS CLI Protocol Version 1

## Boundary And Versioning

The Ruby CLI is the only agent-facing interface to KOS state. It calls the Rails REST API under `/api/v1`, writes exactly one JSON document to stdout when invoked with `--json`, and writes diagnostics only to stderr. Agents do not call the API directly.

Protocol version 1 uses JSON Schema draft 2020-12. Every JSON document contains `"schema_version": "1"`; every schema has a unique `$id` under `https://kos.local/schemas/cli/v1/`; and every `$ref` resolves within `schemas/cli/v1/` without network access. Object properties use `snake_case`, optional values are omitted rather than represented as `null`, timestamps are RFC 3339 UTC date-times, SHA-256 digests use `sha256:<lowercase-hex>`, and Git object IDs are full 40-character lowercase SHA-1 values in this version.

Objects are closed unless their schema explicitly says otherwise. Until a protocol version has an implemented release, its checked-in schemas are a draft and may be corrected when contract verification finds a gap. After the first implemented release, every schema in that version is immutable. Any later change to an existing document shape, enum, command, or meaning requires a new protocol major version and API namespace; a server may support old and new versions concurrently. A new schema that no released document references may be added without changing that version. The API rejects a version it cannot process with `unsupported_schema_version`; it never silently coerces versions.

The normative machine schemas are:

| File | Contract |
| --- | --- |
| `schemas/cli/v1/common.json` | Identifiers, digests, paths, and mutation preconditions |
| `schemas/cli/v1/envelopes.json` | Success and failure envelopes and stable errors |
| `schemas/cli/v1/resources.json` | Repository, task type, workflow, task, attempt, and worktree reservation resources |
| `schemas/cli/v1/artifacts.json` | Immutable artifact inputs and registered artifacts |
| `schemas/cli/v1/workflow.json` | Workflow-step context and result manifests |
| `schemas/cli/v1/commands.json` | Command requests, results, and command-specific payloads |
| `schemas/cli/v1/catalog.json` | Exact CLI/API bindings, preconditions, statuses, and error transport mappings |

## CLI Transport

The stable repository-scoped machine invocation is:

```text
kos <resource> <operation> --repository <repository-id> --json [command options]
```

The sole unscoped command is `kos repository register --input <path|-> --idempotency-key <key> --json`. It creates repository scope and therefore neither accepts `--repository` nor carries `repository_id` in its request. It remains authenticated and uses the same JSON-only mutation transport.

Read options form the logical command `body` defined in `commands.json`. A mutation takes `--input <path|->`, where the file or stdin contains only its command-specific `body`, and requires `--idempotency-key <key>`. The CLI validates input, then forms the complete versioned command request before sending it. A key is 8 to 255 ASCII letters, digits, `.`, `_`, `:`, or `-`. Secrets are never accepted in an input document.

The API base URL comes from `KOS_API_URL` and defaults to `http://127.0.0.1:3000`. The bearer token comes only from `KOS_API_TOKEN`. Every API request except `GET /up` sends `Authorization: Bearer <token>` and `Accept: application/json`; requests with a JSON body also send `Content-Type: application/json`. Mutation requests send the CLI key as `Idempotency-Key`. The key is not duplicated in the JSON payload.

Every scoped endpoint begins `/api/v1/repositories/{repository_id}`. The CLI includes the same immutable `repository_id` in its logical command request; for a mutation, the API body carries that full request and the API rejects a path/body mismatch as `malformed_input`. A filesystem path is never accepted as repository identity. The authenticated registration endpoint is the explicit exception at `POST /api/v1/repositories`; the server verifies its canonical Git common directory and trust settings rather than treating the submitted path as identity proof.

Read commands map their logical body fields to the listed path and query parameters and do not send a GET body. List cursors are opaque, scoped to the repository and command filters, and limited to 255 characters. `limit` is required and ranges from 1 through 100. A response omits `next_cursor` when no next page exists.

`step.context` is an idempotent mutation that requires lock, attempt, and fencing preconditions. The server validates repository scope, current task status, active lease ownership, and fencing token before atomically storing and returning executable project instructions.

The default request timeout is 30 seconds and may be changed with `KOS_API_TIMEOUT_SECONDS` to a positive integer. The CLI makes at most three total attempts for a read or an idempotent mutation, reusing the same idempotency key. It retries only a `transient` failure or a connection failure that it represents as `transport_unavailable`. Before attempts two and three it uses full jitter in `[0, 250ms]` and `[0, 500ms]`; a larger server `retry_after_seconds` replaces that range, subject to the request timeout. It never retries `internal` or any non-transient category automatically.

## Command Catalog

All commands except `repository.register` require `--repository <repository-id> --json`. Read arguments shown below are additional CLI options. Every mutation requires `--input <path|-> --idempotency-key <key>` and obtains path identifiers from the validated input body. Every successful command exits `0`; the command catalog records this common success status as `x-success-cli-exit`.

| Identifier | CLI syntax | HTTP binding | Success |
| --- | --- | --- | --- |
| `repository.register` | `kos repository register` | `POST /api/v1/repositories` | `200` repository |
| `task_type.list` | `kos task-type list --limit N [--cursor C]` | `GET /task-types?limit=N&cursor=C` | `200` task-type page |
| `workflow.list` | `kos workflow list --limit N [--cursor C]` | `GET /workflows?limit=N&cursor=C` | `200` workflow page |
| `workflow.get` | `kos workflow get --workflow ID --version VERSION` | `GET /workflows/{workflow_id}/versions/{version}` | `200` workflow |
| `task.get` | `kos task get --task <task-number>` | `GET /tasks/{task_number}` | `200` task |
| `attempt.get` | `kos attempt get --attempt UUID` | `GET /attempts/{attempt_id}` | `200` attempt |
| `step.context` | `kos step context` | `POST /attempts/{attempt_id}/step-context` | `200` workflow context |
| `worktree.get` | `kos worktree get --reservation UUID` | `GET /worktree-reservations/{reservation_id}` | `200` reservation |
| `artifact.list` | `kos artifact list --task <task-number> --limit N [--cursor C]` | `GET /tasks/{task_number}/artifacts?limit=N&cursor=C` | `200` artifact page |
| `publication.get` | `kos publication get --publication UUID` | `GET /publications/{publication_id}` | `200` publication |
| `task.create` | `kos task create` | `POST /tasks` | `201` task |
| `attempt.claim` | `kos attempt claim` | `POST /tasks/{task_number}/attempts/claim` | `201` attempt |
| `attempt.renew` | `kos attempt renew` | `POST /attempts/{attempt_id}/renew` | `200` attempt |
| `attempt.fail` | `kos attempt fail` | `POST /attempts/{attempt_id}/fail` | `200` attempt |
| `attempt.needs_human` | `kos attempt needs-human` | `POST /attempts/{attempt_id}/needs-human` | `200` attempt |
| `attempt.reconcile` | `kos attempt reconcile` | `POST /attempts/{attempt_id}/reconcile` | `200` attempt |
| `worktree.reserve` | `kos worktree reserve` | `POST /tasks/{task_number}/worktree-reservations` | `201` reservation |
| `worktree.confirm` | `kos worktree confirm` | `POST /worktree-reservations/{reservation_id}/confirm` | `200` reservation |
| `worktree.reconcile` | `kos worktree reconcile` | `POST /worktree-reservations/{reservation_id}/reconcile` | `200` reservation |
| `worktree.release` | `kos worktree release` | `POST /worktree-reservations/{reservation_id}/release` | `200` reservation |
| `artifact.register` | `kos artifact register` | `POST /tasks/{task_number}/artifacts` | `201` artifact |
| `step.complete` | `kos step complete` | `POST /tasks/{task_number}/steps/complete` | `200` task and artifacts |
| `publication.prepare` | `kos publication prepare` | `POST /tasks/{task_number}/publications` | `201` prepared publication |
| `publication.reconcile` | `kos publication reconcile` | `POST /publications/{publication_id}/reconcile` | `200` reconciled publication |
| `publication.complete` | `kos publication complete` | `POST /publications/{publication_id}/complete` | `200` task and artifacts |

The path values are taken from their same-named body fields or leased preconditions and must agree with them. The API stores and replays the original successful status for an idempotent mutation, including `201`.

## Mutation Preconditions

`I` means an `Idempotency-Key` header is required. `L` means `expected_lock_version` is required. `A` means an `attempt_id` is required, and `F` means it must be accompanied by that active attempt's current `fencing_token`. The JSON location is `body.preconditions` except for the explicitly unleased reconciliation payload.

| Commands | I | L | A | F |
| --- | --- | --- | --- | --- |
| `repository.register` | yes | no | no | no |
| `task.create` | yes | no | no | no |
| `attempt.claim` | yes | yes | no | no |
| `step.context` | yes | yes | yes | yes |
| `attempt.reconcile` | yes | yes | yes | no |
| `attempt.renew`, `attempt.fail`, `attempt.needs_human` | yes | yes | yes | yes |
| `worktree.reserve`, `worktree.confirm`, `worktree.reconcile`, `worktree.release` | yes | yes | yes | yes |
| `artifact.register`, `step.complete` | yes | yes | yes | yes |
| `publication.prepare`, `publication.reconcile`, `publication.complete` | yes | yes | yes | yes |

Claim checks the task's expected lock version before creating an attempt and fencing token. Attempt reconciliation is available only after ownership has expired or the attempt is already interrupted; it identifies that attempt but has no live fencing token and cannot itself assert that an external effect succeeded. All mutations owned by a live attempt reject a missing, expired, or stale lease before changing state.

The server scopes an idempotency record by repository and command identifier. `repository.register` instead uses a global scope because no repository exists yet. Its request fingerprint is SHA-256 over the UTF-8 sequence `command`, newline, scope, newline, and the command body serialized with RFC 8785 JSON Canonicalization Scheme, where scope is the repository UUID for scoped commands and the literal `global` for registration. Authorization data, request IDs, and the idempotency key are not fingerprint inputs. Version 1 retains scoped records for the lifetime of the repository registration and retains registration records for the lifetime of the central state.

A repeat with the same key and fingerprint returns the same semantic data and original HTTP status without repeating work; it may have a new `request_id`. After authentication, repository authorization, command recognition, and request-shape validation, lookup of a completed idempotency record precedes mutable resource preconditions such as lock version, lease, and fencing checks. A completed replay therefore remains available after its original lease expires. Reuse with another fingerprint returns `idempotency_conflict`. An unfinished durable intent returns `idempotency_in_progress`; the caller reads or reconciles the named resource instead of blindly resubmitting the effect.

## Attempts, Artifacts, And Completion

`repository.register` accepts the human-selected task prefix, canonical absolute Git common directory, trusted remote name, normalized credential-free URL, and full base ref after the human confirmation required by initialization. The API validates prefix syntax and global availability and independently verifies the Git directory and observed trust settings. A first registration and a matching repeat both return the same closed repository resource and HTTP `200`; a repeat never updates its prefix or trust settings. Invalid prefix syntax or mismatched observed Git data returns `repository_registration_invalid`. An occupied prefix, or a previously registered common directory submitted with a different prefix or trust settings, returns `repository_registration_conflict`. The complete behavior and state ownership are defined by [Central Persistence](central-persistence.md).

Public task numbers combine the owning repository's prefix with a six-digit repository-local sequence, such as `KOS-000123`. A command scoped to a repository rejects a well-formed task number whose prefix differs from that repository's persisted prefix as `task_not_found`; it does not reveal task existence in another repository. Branch values derived from a task number use the exact form `kos/task-<task-number>`. JSON Schema validates each value's shape and marks derivation, commit-context, and candidate-trailer constraints with `x-*` annotations; the API and orchestrator validate equality against the owning task, repository, and frozen context because JSON Schema cannot compare those persisted or transformed values.

Task creation accepts only the title and `quick-fix` task type. The server resolves the current workflow from the repository's authoritative configuration, creates its content-addressed snapshot, and returns the pinned workflow identity, version, and bundle digest on the task. A client cannot select or assert those values.

After claim and confirmation of any required worktree, `step.context` constructs the complete executable context from the task, active attempt, current status, and pinned snapshot. In one transaction it stores the immutable context and its digest on the attempt and returns the exact UTF-8 Markdown instruction, all directly referenced UTF-8 materials, their repository-relative `.kos/...` paths, media types, and content digests together with the server-derived capability allowlist and artifact requirements. Each required artifact contains its type, cardinality (`one` or `many`), subject (`task` or `candidate`), and nonempty allowed-state set; requirements are unique by type and use the same type/state/subject compatibility rules as project schema version 1. It never returns a snapshot root, storage path, or caller-selected bundle member. Members are sorted by path and paths are unique. Limits are measured over UTF-8 bytes, not Unicode characters: an instruction is at most 128 KiB, each material is at most 1 MiB, and all instruction and material content together is at most 4 MiB. The workflow schema exposes these application-level constraints as `x-*` contract annotations because JSON Schema `maxLength` counts characters rather than bytes and cannot express ordering or uniqueness by one object property.

An instruction or material digest is SHA-256 over the exact stored file bytes, without newline, Unicode, or whitespace normalization, represented as `sha256:<lowercase-hex>`. Every returned member must be valid UTF-8, and its JSON `content` re-encoded as UTF-8 must reproduce those bytes. `input_context_digest` is SHA-256 over the RFC 8785 canonical JSON serialization of the complete `workflow.json#/$defs/context` object with only `input_context_digest` omitted. This binds instruction content, materials, capabilities, artifact requirements, worktree, and all other context fields to the result manifest without a circular digest input.

A newly claimed attempt omits `input_context_digest` until `step.context` freezes its input. Repeating `step.context` with the same idempotency key returns the original response; a later call for the same active attempt returns the same frozen context rather than rebuilding it from changed repository or task state. `attempt.fail`, `attempt.needs_human`, `step.complete`, and `publication.complete` compare the manifest digest with the stored digest. A status requiring a worktree cannot freeze executable context until its reservation is confirmed.

`step.context` returns `context_unavailable` when the attempt is not active for the task's current status or a required worktree is not confirmed. Normal lease and fencing failures retain `lease_expired` and `fencing_token_stale`. Missing resources retain their resource-specific `not_found` codes. A missing member, digest mismatch, invalid UTF-8 member, path escape, duplicate material path, unsorted material list, or content-size violation in the pinned snapshot returns `bundle_inconsistent`; KOS does not return partially verified instructions.

`attempt.fail` accepts only a `failed` result manifest. `attempt.needs_human` accepts only a `needs_human` manifest and releases the lease. Neither command advances workflow status. No result can be submitted before context is frozen. `step.complete` accepts a `succeeded` manifest and atomically verifies the stored context digest, lease, lock version, transition, dependencies, artifact contracts, candidate generation, and distinct review attempt before registering the supplied artifacts, marking the attempt succeeded, and advancing workflow status.

Artifact type and state pairs are closed in version 1: `document` and `candidate` use `produced`; `test` uses `passed` or `failed`; `review` uses `approved` or `changes_requested`; and `publication` uses `published`. Candidate-specific evidence must name the exact candidate SHA. A standalone `artifact.register` records only a workflow-declared durable non-transition artifact; it never satisfies a transition retroactively. Artifacts required by a successful transition must be supplied to `step.complete` or `publication.complete`.

The versioned workflow context and result manifest are the complete data exchange with a subagent. A result may request only the closed set of typed `kos-repository` effects in `workflow.json`: worktree creation or removal, commit, fetch, rebase, or push. Each request carries operation-specific reservation, expected Git state, or prepared-publication preconditions. A commit request identifies repository-relative paths, message, task number, expected HEAD, and SHA-256 digests of the expected worktree diff and staged index; `kos-repository` verifies those values and appends `KOS-Task: <task-number>` before committing. `expected_diff_digest` hashes the exact bytes from `git diff --binary --full-index --no-ext-diff <expected-head> -- <byte-sorted-paths>`. `expected_index_digest` hashes the NUL-delimited, byte-sorted `<mode> <blob-oid>\t<path>` entries expected from `git ls-files --stage -z -- <paths>` after staging those paths. Git runs without external diff or color configuration. A subagent cannot add capabilities, execute an effect, mutate KOS state, or claim a different attempt. The orchestrator verifies the returned attempt ID, input-context digest, allowed operation, lease, and fencing token before invoking `kos-repository`; it may then add the adapter's validated artifact evidence to the manifest it submits, but cannot change the subagent's outcome or substantive result.

## External-Effect Recovery

Worktree allocation follows reserve, external materialization by `kos-repository`, and confirm. Reconciliation accepts only the schema's observed states and evidence digest. A dirty or mismatched worktree cannot be adopted or automatically removed. For the MVP, terminal cleanup runs as a separate idempotent `worktree.release` operation while the publication attempt still owns its lease and before `publication.complete`; completion requires any allocated reservation to be `released`. If cleanup is interrupted, the attempt and reservation are reconciled before completion. A dirty or unknown worktree blocks automatic completion and requires human resolution rather than deletion.

Publication follows these commands:

1. `publication.prepare` validates the reviewed candidate, trusted remote and full base ref, records the expected remote OID and durable intent, stores its ID on the task as `active_publication_id`, and returns the publication resource.
2. `kos-repository` runs checks and performs a conditional fast-forward push of the exact candidate outside the database transaction.
3. After every push response, including an unknown response, `kos-repository` fetches the trusted remote and returns the observed tip, reachability, time, and evidence digest to `publication.reconcile`.
4. If the candidate is reachable, the orchestrator safely releases the task worktree and calls `publication.complete`, which atomically verifies the prepared operation and successful manifest, registers its matching publication artifact, marks the attempt succeeded, and advances the task to `completed`.

The publication resource durably returns the latest observed remote tip, candidate reachability, observation time and evidence digest after reconciliation. If the candidate is not reachable and the observed tip still equals the prepared expected OID, the same prepared effect may be retried. If the observed tip moved, reconciliation marks the publication `superseded`, clears the task's `active_publication_id`, and returns `base_moved`; a new publication may be prepared only for a newly checked and reviewed candidate generation. Successful completion also clears `active_publication_id`. Client-supplied observations are accepted only from the current owning orchestrator as output of `kos-repository`; later adapter contract tests must prove how that evidence is generated.

After lease expiry, `task.get` exposes `active_publication_id`. The new orchestrator first reconciles the expired attempt, then claims the same task and workflow status. That claim atomically adopts each unresolved durable intent by setting its `current_owner_attempt_id` to the new attempt without changing its prepared parameters. The new owner uses `publication.get`, observes the remote through `kos-repository`, and reconciles the existing publication. A second `publication.prepare` is rejected while an unresolved publication exists.

## Response And Errors

Every API and `--json` CLI result uses `commands.json#/$defs/result` or `envelopes.json#/$defs/failure`. It contains the protocol version, server- or CLI-generated UUID `request_id`, and command identifier. Success contains `data`; failure contains one `error`. Stack traces, tokens, environment values, absolute secret-bearing paths, and unfiltered adapter output are forbidden in responses.

CLI exit statuses are stable by category:

| Category | HTTP | CLI | Retry |
| --- | --- | --- | --- |
| `validation` | `400` or `422` | `2` | no |
| `authentication` | `401` | `3` | no |
| `authorization` | `403` | `4` | no |
| `not_found` | `404` | `5` | no |
| `conflict` | `409` | `6` | no |
| `lease_lost` | `409` | `7` | no |
| `transient` | `503` or `504` | `8` | yes |
| `internal` | `500` | `1` | no |

The stable leaf-code mapping is:

| Category | Codes |
| --- | --- |
| `validation` | `malformed_input` (`400`), `unsupported_schema_version` (`400`), `unknown_command` (`400`), `invalid_artifact` (`422`), `repository_registration_invalid` (`422`) |
| `authentication` | `authentication_required`, `invalid_token` |
| `authorization` | `forbidden`, `repository_access_denied` |
| `conflict` | `stale_lock_version`, `invalid_transition`, `idempotency_conflict`, `idempotency_in_progress`, `dependency_unsatisfied`, `base_moved`, `context_unavailable`, `bundle_inconsistent`, `repository_registration_conflict` |
| `lease_lost` | `lease_expired`, `fencing_token_stale` |
| `not_found` | `task_not_found`, `workflow_not_found`, `attempt_not_found`, `reservation_not_found`, `artifact_not_found`, `publication_not_found` |
| `transient` | `transport_unavailable` (`503`), `request_timeout` (`504`) |
| `internal` | `internal_error` |

Codes without an HTTP override use their category's status. `details` may contain only schema-approved safe fields such as the invalid field, expected and actual scalar, resource identifier, or retry delay. The CLI uses the same envelope and exit status for local validation and transport failures, so callers never have to parse stderr.

After authentication, an absent and an unauthorized repository both return `repository_access_denied` with `403`; the API does not reveal repository registration through different errors. An unrecognized CLI operation uses `command: "unknown"` with `unknown_command`; every other response carries a cataloged command identifier.

## Contract Verification

Every schema must validate against its metaschema, have a unique versioned `$id`, and resolve all references locally. Contract tests cover every command request and result, every artifact discriminator and allowed state, both response envelopes, terminal attempt outcomes, optimistic and fencing preconditions, publication completion, and representative malformed documents. API and CLI implementations must consume these schemas rather than define divergent wire shapes.
