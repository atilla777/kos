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
| `schemas/cli/v1/workflow_definition.json` | Central workflow draft and publication document |
| `schemas/cli/v1/artifacts.json` | Immutable artifact inputs and registered artifacts |
| `schemas/cli/v1/workflow.json` | Workflow-step context, typed effect round trips, and result manifests |
| `schemas/cli/v1/commands.json` | Command requests, results, and command-specific payloads |
| `schemas/cli/v1/catalog.json` | Exact CLI/API bindings, preconditions, statuses, and error transport mappings |

## CLI Transport

The stable repository-scoped machine invocation is:

```text
kos <resource> <operation> --repository <repository-id> --json [command options]
```

Shared workflow-catalog and runtime-configuration commands are authenticated global commands and omit `--repository`. Repository registration is a separate global-creation scope because it establishes a repository identity. Representative forms are:

```text
kos workflow list --limit N --json
kos workflow-draft import --input <path|-> --idempotency-key <key> --json
kos repository register --input <path|-> --idempotency-key <key> --json
```

Read options form the logical command `body` defined in `commands.json`. A mutation takes `--input <path|->`, where the file or stdin contains only its command-specific `body`, and requires `--idempotency-key <key>`. The CLI validates input, then forms the complete versioned command request before sending it. A key is 8 to 255 ASCII letters, digits, `.`, `_`, `:`, or `-`. Secrets are never accepted in an input document.

The API base URL comes from `KOS_API_URL` and defaults to `http://127.0.0.1:3000`. The bearer token comes only from `KOS_API_TOKEN`. Every API request except `GET /up` sends `Authorization: Bearer <token>` and `Accept: application/json`; requests with a JSON body also send `Content-Type: application/json`. Mutation requests send the CLI key as `Idempotency-Key`. The key is not duplicated in the JSON payload.

Every repository-scoped endpoint begins `/api/v1/repositories/{repository_id}`. The CLI includes the same immutable `repository_id` in its logical command request; for a mutation, the API body carries that full request and the API rejects a path/body mismatch as `malformed_input`. A filesystem path is never accepted as repository identity. Authenticated global catalog endpoints begin directly under `/api/v1`; their requests must omit `repository_id`. Registration remains `POST /api/v1/repositories`, and the server verifies its canonical Git common directory and trust settings rather than treating the submitted path as identity proof.

Read commands map their logical body fields to the listed path and query parameters and do not send a GET body. List cursors are opaque, scoped to the repository and command filters, and limited to 255 characters. `limit` is required and ranges from 1 through 100. A response omits `next_cursor` when no next page exists.

`step.context` is an idempotent mutation that requires lock, attempt, and fencing preconditions. The server validates repository scope, current task status, active lease ownership, and fencing token before atomically storing and returning executable instructions from the task's immutable workflow version.

The default request timeout is 30 seconds and may be changed with `KOS_API_TIMEOUT_SECONDS` to a positive integer. The CLI makes at most three total attempts for a read or an idempotent mutation, reusing the same idempotency key. It retries only a `transient` failure or a connection failure that it represents as `transport_unavailable`. Before attempts two and three it uses full jitter in `[0, 250ms]` and `[0, 500ms]`; a larger server `retry_after_seconds` replaces that range, subject to the request timeout. It never retries `internal` or any non-transient category automatically.

## Command Catalog

Repository task and execution commands require `--repository <repository-id> --json`. Shared catalog, runtime configuration, and repository-registration commands omit it. Read arguments shown below are additional CLI options. Every mutation requires `--input <path|-> --idempotency-key <key>` and obtains path identifiers from the validated input body. Every successful command exits `0`; the command catalog records this common success status as `x-success-cli-exit`.

| Identifier | CLI syntax | HTTP binding | Success |
| --- | --- | --- | --- |
| `repository.register` | `kos repository register` | `POST /api/v1/repositories` | `200` repository |
| `runtime_config.get` | `kos runtime-config get` | `GET /api/v1/runtime-config` | `200` runtime config |
| `runtime_config.update` | `kos runtime-config update` | `POST /api/v1/runtime-config` | `200` runtime config |
| `task_type.list` | `kos task-type list --limit N [--cursor C]` | `GET /api/v1/task-types?limit=N&cursor=C` | `200` task-type page |
| `workflow.list` | `kos workflow list --limit N [--cursor C]` | `GET /api/v1/workflow-versions?limit=N&cursor=C` | `200` workflow-version page |
| `workflow.get` | `kos workflow get --workflow-version UUID` | `GET /api/v1/workflow-versions/{workflow_version_id}` | `200` workflow version |
| `workflow.export` | `kos workflow export --workflow-version UUID` | `GET /api/v1/workflow-versions/{workflow_version_id}/export` | `200` workflow definition |
| `workflow_draft.get` | `kos workflow-draft get --workflow ID` | `GET /api/v1/workflow-drafts/{workflow_id}` | `200` workflow draft |
| `workflow_draft.import` | `kos workflow-draft import` | `POST /api/v1/workflow-drafts/{workflow_id}` | `200` workflow draft |
| `workflow_draft.validate` | `kos workflow-draft validate --workflow ID` | `GET /api/v1/workflow-drafts/{workflow_id}/validation` | `200` validation result |
| `workflow.publish` | `kos workflow publish` | `POST /api/v1/workflow-drafts/{workflow_id}/publication` | `201` workflow version |
| `workflow.activate` | `kos workflow activate` | `POST /api/v1/task-types/{task_type}/current-workflow` | `200` task type |
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
| `effect.get` | `kos effect get --effect UUID` | `GET /repository-effects/{effect_id}` | `200` repository effect |
| `effect.prepare` | `kos effect prepare` | `POST /tasks/{task_number}/repository-effects` | `201` prepared repository effect |
| `effect.reconcile` | `kos effect reconcile` | `POST /repository-effects/{effect_id}/reconcile` | `200` reconciled repository effect |
| `artifact.register` | `kos artifact register` | `POST /tasks/{task_number}/artifacts` | `201` artifact |
| `step.complete` | `kos step complete` | `POST /tasks/{task_number}/steps/complete` | `200` task and artifacts |
| `publication.prepare` | `kos publication prepare` | `POST /tasks/{task_number}/publications` | `201` prepared publication |
| `publication.reconcile` | `kos publication reconcile` | `POST /publications/{publication_id}/reconcile` | `200` reconciled publication |
| `publication.complete` | `kos publication complete` | `POST /publications/{publication_id}/complete` | `200` task and artifacts |

The path values are taken from their same-named body fields or leased preconditions and must agree with them. The API stores and replays the original successful status for an idempotent mutation, including `201`.

## Mutation Preconditions

`I` means an `Idempotency-Key` header is required. `L` means `expected_lock_version` is required. `A` means an `attempt_id` is required, and `F` means it must be accompanied by that active attempt's current `fencing_token`. The JSON location is `body.preconditions` for task execution, while global catalog mutations carry their resource lock directly in `body`.

| Commands | I | L | A | F |
| --- | --- | --- | --- | --- |
| `repository.register` | yes | no | no | no |
| `runtime_config.update`, `workflow_draft.import`, `workflow.publish`, `workflow.activate` | yes | yes | no | no |
| `task.create` | yes | no | no | no |
| `attempt.claim` | yes | yes | no | no |
| `step.context` | yes | yes | yes | yes |
| `attempt.reconcile` | yes | yes | yes | no |
| `attempt.renew`, `attempt.fail`, `attempt.needs_human` | yes | yes | yes | yes |
| `worktree.reserve`, `worktree.confirm`, `worktree.reconcile`, `worktree.release` | yes | yes | yes | yes |
| `effect.prepare`, `effect.reconcile` | yes | yes | yes | yes |
| `artifact.register`, `step.complete` | yes | yes | yes | yes |
| `publication.prepare`, `publication.reconcile`, `publication.complete` | yes | yes | yes | yes |

Claim checks the task's expected lock version before creating an attempt and fencing token. A live or expired but unreconciled started attempt blocks another claim with `invalid_transition`. The attempt ID and current fencing token are the authority for leased mutations. Renewal records its heartbeat and sets expiry to that time plus the requested duration; expiry equality means the lease is already expired, and fencing mismatch takes precedence when both checks fail. Attempt reconciliation is available only after ownership has expired or the attempt is already interrupted; it identifies that attempt but has no live fencing token and cannot itself assert that an external effect succeeded. It durably records immutable observation state, evidence digest, and observation time. An interrupted record created before reconciliation was implemented may attach that evidence once. A repeat for an already reconciled interrupted attempt returns it only when the evidence matches; different evidence returns `invalid_transition`. All mutations owned by a live attempt reject a missing, expired, or stale lease before changing state.

The server scopes an idempotency record by command and either repository UUID or the literal `global`. Catalog, runtime-configuration, and repository-registration mutations use the global scope; repository task and execution mutations use their repository UUID. The request fingerprint is SHA-256 over the UTF-8 sequence `command`, newline, scope, newline, and the command body serialized with RFC 8785 JSON Canonicalization Scheme. Authorization data, request IDs, and the idempotency key are not fingerprint inputs. Version 1 retains these records for the lifetime of the central state or owning repository registration.

A repeat with the same key and fingerprint returns the same semantic data and original HTTP status without repeating work; it may have a new `request_id`. After authentication, repository authorization, command recognition, and request-shape validation, lookup of a completed idempotency record precedes mutable resource preconditions such as lock version, lease, and fencing checks. A completed replay therefore remains available after its original lease expires. Reuse with another fingerprint returns `idempotency_conflict`. An unfinished durable intent returns `idempotency_in_progress`; the caller reads or reconciles the named resource instead of blindly resubmitting the effect.

## Attempts, Artifacts, And Completion

`repository.register` accepts the human-selected task prefix, canonical absolute Git common directory, trusted remote name, normalized credential-free URL, and full base ref after the human confirmation required by initialization. The API validates prefix syntax and global availability and independently verifies the Git directory and observed trust settings. A first registration and a matching repeat both return the same closed repository resource and HTTP `200`; a repeat never updates its prefix or trust settings. Invalid prefix syntax or mismatched observed Git data returns `repository_registration_invalid`. An occupied prefix, or a previously registered common directory submitted with a different prefix or trust settings, returns `repository_registration_conflict`. The complete behavior and state ownership are defined by [Central Persistence](central-persistence.md).

Public task numbers combine the owning repository's prefix with a six-digit repository-local sequence, such as `KOS-000123`. A command scoped to a repository rejects a well-formed task number whose prefix differs from that repository's persisted prefix as `task_not_found`; it does not reveal task existence in another repository. Branch values derived from a task number use the exact form `kos/task-<task-number>`. JSON Schema validates each value's shape and marks derivation, commit-context, and candidate-trailer constraints with `x-*` annotations; the API and orchestrator validate equality against the owning task, repository, and frozen context because JSON Schema cannot compare those persisted or transformed values.

Workflow draft import accepts a top-level workflow identity, the matching complete closed workflow definition, and expected draft lock version. A path, top-level identity, and embedded definition identity mismatch is `malformed_input`. Validation reports whole-graph errors without publishing. Publication validates the same complete draft and atomically creates an immutable workflow version; reusing a workflow semantic version with different content is `workflow_version_conflict`. Activation requires the task type lock version and a published version belonging to that type. Export returns the complete canonical definition used to compute the version's content digest.

Task creation accepts only the title and `quick-fix` task type. In its transaction, the server resolves the task type's current published version and stores its immutable `workflow_version_id` and initial state on the task. A client cannot select or assert a workflow version. Later activation changes do not affect that task.

A task title must contain at least one non-whitespace character. Creation returns `task_type_unavailable` without allocating a number when the task type has no active published workflow version. After sequence `999999`, creation returns `task_number_exhausted` without widening, wrapping, or changing the exhausted sequence. Both failures are nonretryable conflicts.

After claim and confirmation of any required worktree, `step.context` constructs the complete executable context from the task, active attempt, current status, and pinned workflow version. A publication attempt first prepares or adopts its durable publication resource. Until that resource and operation are implemented, `step.context` returns `context_unavailable` for publication rather than returning a partial context. In one transaction `step.context` stores the immutable context and its digest on the attempt and returns the exact UTF-8 Markdown instruction, optional inline artifact templates, artifact requirements, allowed typed repository effects, installation retrospective setting, and prepared publication parameters when applicable. Each required artifact contains its type, cardinality (`one` or `many`), subject (`task` or `candidate`), and nonempty allowed-state set. Requirements are unique by type. An instruction is at most 128 KiB, each template is at most 1 MiB, and one state's instruction and templates total at most 4 MiB, measured over UTF-8 bytes.

`input_context_digest` is SHA-256 over the RFC 8785 canonical JSON serialization of the complete `workflow.json#/$defs/context` object with only `input_context_digest` omitted. This binds instruction and template content, allowed effects, retrospective setting, artifact requirements, worktree, and all other context fields to the result manifest without separate member digests or a circular digest input.

A newly claimed attempt omits `input_context_digest` until `step.context` freezes its input. Repeating `step.context` with the same idempotency key returns the original response; a later call for the same active attempt returns the same frozen context rather than rebuilding it from changed repository or task state. `attempt.fail`, `attempt.needs_human`, `step.complete`, and `publication.complete` compare the manifest digest with the stored digest. A status requiring a worktree cannot freeze executable context until its reservation is confirmed.

`step.context` returns `context_unavailable` when the attempt is not active for the task's current status, the task's state does not belong to its pinned version, or a required worktree is not confirmed. Normal lease and fencing failures retain `lease_expired` and `fencing_token_stale`. Missing resources retain their resource-specific `not_found` codes. Invalid stored content is an internal invariant failure; KOS never returns a partial executable context.

`attempt.fail` accepts only a `failed` result manifest. `attempt.needs_human` accepts only a `needs_human` manifest and releases the lease. Neither command advances workflow status or registers its manifest artifacts as `TaskArtifact` rows; those entries remain durable in the immutable manifest. No result can be submitted before context is frozen, and missing or mismatched frozen context returns `context_unavailable`. `step.complete` accepts a `succeeded` manifest and atomically verifies the stored context digest, lease, lock version, transition, dependencies, artifact contracts, candidate generation, and distinct review attempt before registering the supplied artifacts, marking the attempt succeeded, and advancing workflow status.

Artifact type and state pairs are closed in version 1: `document` and `candidate` use `produced`; `test` uses `passed` or `failed`; `review` uses `approved` or `changes_requested`; and `publication` uses `published`. Candidate-specific evidence must name the exact candidate SHA. A standalone `artifact.register` records only a workflow-declared durable non-transition artifact; it never satisfies a transition retroactively. Artifacts required by a successful transition must be supplied to `step.complete` or `publication.complete`.

The versioned workflow context, typed effect request/results, and final result manifest are the complete primary workflow data exchange with a subagent. Before returning its final manifest, the executor may send a typed effect request bound to the attempt and input-context digest. `effect_request_digest` is SHA-256 over the RFC 8785 canonical JSON serialization of the complete `workflow.json#/$defs/effect_request` object. Every typed result carries that digest, the request attempt, current owning attempt, durable intent identifier, and explicit `succeeded`, `failed`, or `unknown` outcome. A success contains operation-specific observed evidence; failure and unknown outcomes contain a closed safe error with category, code, message, and retryability. The result operation must equal the requested operation. For generic commit/fetch/rebase effects the intent identifier names the repository-effect resource; worktree removal and push use the reservation and publication identifiers respectively.

The orchestrator verifies the active lease, fencing token, operation membership in the frozen allowlist, and operation-specific preconditions. A commit or rebase request's reservation and expected HEAD must equal the frozen worktree context; a commit's task number must equal the owning task. For commit, fetch, or rebase it calls `effect.prepare` before invoking `kos-repository` and `effect.reconcile` with every success, failure, or unknown response. Worktree removal uses `worktree.release`; push uses the publication resource prepared before context finalization. The orchestrator returns the resulting typed observation to that same executor session. A commit success includes the created commit SHA; publication effects return observed remote evidence. The executor then constructs final artifact metadata against those actual values. The final manifest contains artifacts and outcome, not pending effect requests.

A commit request identifies repository-relative paths, message, task number, expected HEAD, and SHA-256 digests of the expected worktree diff and staged index; `kos-repository` verifies those values and appends `KOS-Task: <task-number>` before committing. `expected_diff_digest` hashes the exact bytes from `git diff --binary --full-index --no-ext-diff --no-textconv <expected-head> -- <byte-sorted-paths>`. `expected_index_digest` hashes the NUL-delimited, byte-sorted `<mode> <blob-oid>\t<path>` entries expected from `git ls-files --stage -z -- <paths>` after staging those paths. Git runs without external diff, text conversion, or color configuration. A subagent cannot add an allowed effect, invoke `kos-repository` directly, mutate KOS state, or claim a different attempt. The final manifest remains the executor's substantive result; the orchestrator cannot rewrite its outcome or evidence.

## External-Effect Recovery

`effect.prepare` stores the exact request and canonical digest before commit, fetch, or rebase. Only then may the orchestrator invoke `kos-repository`. `effect.reconcile` records a typed success or failure; an unavailable or lost adapter response records an `unknown` state and requires observation of the expected HEAD, refs, index, and worktree before retry or terminal reconciliation. A task may retain multiple generic effects. `prepared` and `unknown` effects are unresolved; `succeeded` and `failed` effects are terminal and immutable. An owning attempt cannot fail, enter needs-human, or complete its step while one of its generic effects remains unresolved.

The resource retains its preparing attempt and current owning attempt. After lease expiry, attempt reconciliation reports `repository_effect_pending` exactly when the attempt owns an unresolved generic effect; another observation classification is inconsistent. A new claim atomically adopts every unresolved generic effect without changing its request, reads each one with `effect.get`, and reconciles observed state. Adoption updates the current-owner attribution in a retained `unknown` result so the closed resource remains bound to its current owner. The new owner may reconcile `unknown` to `succeeded`, `failed`, or a replacement `unknown`; version 1 retains only the latest result. It never blindly resubmits an unknown effect.

Worktree allocation follows reserve, external materialization by `kos-repository`, and confirm. Reconciliation accepts only the schema's observed states and evidence digest. A dirty or mismatched worktree cannot be adopted or automatically removed. For the MVP, terminal cleanup runs as a separate idempotent `worktree.release` operation while the publication attempt still owns its lease and before `publication.complete`; completion requires any allocated reservation to be `released`. If cleanup is interrupted, the attempt and reservation are reconciled before completion. A dirty or unknown worktree blocks automatic completion and requires human resolution rather than deletion.

`worktree.reserve` validates the exact task-derived branch and a lexically canonical absolute path, persists the allocation, and attaches it to the task without touching the filesystem. `worktree.confirm` compares `git_common_dir_digest` with SHA-256 over the repository's persisted canonical UTF-8 common-directory path and records the confirmed HEAD. After attempt reconciliation, a new claim adopts an unresolved reservation by updating only its owner attempt and fencing token. A clean `worktree.reconcile` observation requires `head_sha` and may confirm a reserved allocation; an absent observation preserves an unmaterialized reservation but completes a materialized release. Dirty and mismatched observations remain durable blockers.

Cleanup uses `worktree.release` twice around the external removal. A clean observation whose HEAD equals the confirmed reservation moves it to `release_pending`; after `kos-repository` removes it, an absent observation atomically clears the task pointer and marks it `released`. An absent observation can also complete recovery when removal succeeded but its response was lost. Same-key replay remains available after lease loss, while a new mutation key requires the reservation's current owning attempt and fencing token.

Publication follows these commands:

1. `publication.prepare` validates the reviewed candidate, trusted remote and full base ref, records the expected remote OID and durable intent, stores its ID on the task as `active_publication_id`, and returns the publication resource.
2. The orchestrator verifies the approved review, mandatory checks, active lease and fencing token, frozen context, task version, and prepared publication before invoking `kos-repository` outside the database transaction.
3. `kos-repository` first fetches the trusted remote. It returns an already-reachable or moved-base observation without pushing; only an unchanged expected tip and verified fast-forward relation permit an exact-old-OID conditional push of the candidate.
4. After every push response, including an unknown response, `kos-repository` fetches the trusted remote and returns the observed tip, reachability, time, and evidence digest to `publication.reconcile`.
5. If the candidate is reachable, the orchestrator safely releases the task worktree and calls `publication.complete`, which atomically verifies the prepared operation and successful manifest, registers its matching publication artifact, marks the attempt succeeded, and advances the task to `completed`.

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
| `validation` | `malformed_input` (`400`), `unsupported_schema_version` (`400`), `unknown_command` (`400`), `invalid_artifact` (`422`), `repository_registration_invalid` (`422`), `workflow_definition_invalid` (`422`) |
| `authentication` | `authentication_required`, `invalid_token` |
| `authorization` | `forbidden`, `repository_access_denied` |
| `conflict` | `stale_lock_version`, `invalid_transition`, `idempotency_conflict`, `idempotency_in_progress`, `dependency_unsatisfied`, `base_moved`, `context_unavailable`, `workflow_version_conflict`, `task_number_exhausted`, `task_type_unavailable`, `repository_registration_conflict` |
| `lease_lost` | `lease_expired`, `fencing_token_stale` |
| `not_found` | `task_not_found`, `workflow_not_found`, `workflow_draft_not_found`, `workflow_version_not_found`, `attempt_not_found`, `reservation_not_found`, `effect_not_found`, `artifact_not_found`, `publication_not_found` |
| `transient` | `transport_unavailable` (`503`), `request_timeout` (`504`) |
| `internal` | `internal_error` |

Codes without an HTTP override use their category's status. `details` may contain only schema-approved safe fields such as the invalid field, expected and actual scalar, resource identifier, or retry delay. The CLI uses the same envelope and exit status for local validation and transport failures, so callers never have to parse stderr.

After authentication, an absent and an unauthorized repository both return `repository_access_denied` with `403`; the API does not reveal repository registration through different errors. An unrecognized CLI operation uses `command: "unknown"` with `unknown_command`; every other response carries a cataloged command identifier.

## Contract Verification

Every schema must validate against its metaschema, have a unique versioned `$id`, and resolve all references locally. Contract tests cover every command request and result, every artifact discriminator and allowed state, both response envelopes, terminal attempt outcomes, optimistic and fencing preconditions, publication completion, and representative malformed documents. API and CLI implementations must consume these schemas rather than define divergent wire shapes.
