---
name: kos-repository
description: Use only as the lease-owning orchestrator to execute persisted typed Git effects through the closed KOS repository adapter contract.
---

# KOS Repository Adapter

## Authority Boundary

Use the installed `kos-repository` executable as the sole executor of mutating Git operations. It is a technical adapter: it does not call KOS state, establish current workflow authority, or decide whether an observation completes a workflow step.

- Invoke this skill only as the lease-owning orchestrator for the current attempt.
- Never use this skill from a workflow-step subagent. A subagent requests an allowed typed effect from its orchestrator and never invokes `kos-repository`, `git`, the KOS API, or the state CLI itself.
- Use `kos` as the only agent-facing interface to KOS state. Never call Rails, its REST API, SQLite, or persistence code directly.
- Before every adapter invocation, read authoritative KOS state and verify the task, its current lock version, the active attempt, unexpired lease, fencing token, and matching current reservation, generic effect, or publication.
- Materialization and lifecycle observation occur before context finalization when required. For a workflow-requested effect, also verify the finalized input-context digest and effect allowlist. The workflow operation `worktree_remove` maps only to adapter operation `remove`.
- Treat adapter snapshots as untrusted until they agree with that fresh state. The adapter validates internal consistency but does not query Rails or independently prove that an owner or fencing token is current.
- Stop all repository work immediately after lease loss or a fencing mismatch. Do not reuse request snapshots from the former owner.

## Durable Intent First

Every operation belongs to an existing durable protocol. Never invoke the adapter for an ad hoc Git command.

| Operation | Required durable authority |
| --- | --- |
| `materialize` | Current `reserved` worktree reservation and its exact expected base commit |
| `observe` | Current `reserved`, `confirmed`, or `release_pending` worktree reservation |
| `remove` | Allowed `worktree_remove` effect and current `release_pending` worktree reservation after a matching clean observation |
| `commit` | Current `confirmed` reservation and a prepared durable `commit` effect |
| `fetch` | Prepared or adopted durable `fetch` effect and registered repository trust snapshot |
| `rebase` | Current `confirmed` reservation, prepared or adopted durable `rebase` effect, and complete verified fetch request and result |
| `push` | Prepared or adopted publication, current task version, approved review and required-check evidence for the exact candidate, and registered publication target |

`observe` means worktree observation only. Version 1 has no generic adapter command for observing or reconciling a commit, fetch, or rebase effect. Never invent one.

Immediately before invocation, use current values returned by `kos`. Never infer, repair, normalize, or substitute a repository ID, attempt ID, reservation ID, effect ID, publication ID, path, branch, remote, ref, commit, digest, owner, fencing token, or state transition. For `commit`, the durable effect identity is checked by the orchestrator even though version 1 does not include that identity in the adapter request.

## Invocation Contract

Invoke exactly one of the implemented operations in this form:

```text
kos-repository <materialize|observe|remove|commit|fetch|rebase|push> --input <path|-> --json
```

- Use `kos-repository`, not a path into a KOS source checkout.
- Prefer `--input -` when the closed request document can be supplied without a temporary file.
- Pass the executable and every argument as a process argument array. Never interpolate task, workflow, artifact, or model input into a shell command.
- The operation argument must equal the request's `operation`.
- Supply exactly one JSON object conforming to `schemas/repository/v1/adapter.json#/$defs/request`, with `schema_version` exactly `"1"` and no additional properties.
- Keep stdout and stderr separate. Stdout is the single machine result; stderr is diagnostics only and may not be parsed as state or evidence.
- The adapter has no API token, repository flag, idempotency key, or built-in retry loop. Do not copy those properties from the `kos` state CLI.

## Implemented Operations

| Operation | Adapter behavior |
| --- | --- |
| `materialize` | Create or verify only the exact reserved task worktree and branch at the expected base commit. |
| `observe` | Return a bounded `absent`, `clean`, `dirty`, or `mismatched` worktree observation without mutation. |
| `remove` | Remove only an exactly matching clean `release_pending` worktree; never delete its branch. |
| `commit` | Verify exact paths, diff and index digests, create the explicit commit with one task trailer, and compare-and-swap the reserved branch. |
| `fetch` | Fetch only the registered base ref from the registered trusted remote without updating local refs. |
| `rebase` | Replay the verified linear task-commit suffix onto the verified fetched base. |
| `push` | Observe and conditionally publish the exact candidate to the registered base ref, then observe candidate reachability. |

Do not invoke an operation absent from this table. Do not use the adapter to run project checks, choose paths, create commit messages, approve candidates, select transitions, classify publication completion, or make any other workflow decision.

## Validate Every Result

Capture stdout, stderr, and process exit status separately. The executable validates its own output against the closed schema; independently fail closed unless all of these checks pass:

1. Stdout contains exactly one JSON object and no prose.
2. `schema_version` is exactly `"1"`.
3. `operation` equals the operation invoked; `unknown` is valid only for malformed invocation input.
4. `outcome` is exactly one of the schema-valid `succeeded`, `failed`, or push-only `unknown` branches.
5. The complete document validates against `adapter.json#/$defs/success` or `adapter.json#/$defs/failure`, as appropriate.
6. Exit status is `0` for `succeeded`, or matches the error category for `failed` or `unknown`.
7. Every returned repository, reservation, effect, publication, current-owner, fencing-token, request-digest, candidate, and operation field equals the invocation and fresh authoritative KOS snapshot wherever that field applies. Immediately before `push`, recheck that the current task version, prepared publication, approved review, and required checks all bind the exact candidate and target.
8. Every required observation or evidence field is present. Never derive a missing identity, SHA, digest, reachability value, or observation from stderr or a human-readable message.

| Exit | Category | Meaning |
| ---: | --- | --- |
| 0 | success | A validated adapter observation, not workflow completion |
| 1 | `internal` | Fail closed; do not retry automatically |
| 2 | `validation` | Reject the request or stale snapshot; do not retry unchanged input |
| 6 | `conflict` | Preserve the conflict for the matching durable protocol; do not override it |
| 8 | `transient` | The operation may be uncertain; do not treat `retryable: true` as authority to repeat it |

Only `transient` errors have `retryable: true`. All other errors require `retryable: false`. Branch on `outcome`, category, code, and retryability, never on message text or stderr.

## Reconcile Observations

An exit status of `0` means that the adapter returned a valid observation. It does not mean that a workflow effect, worktree lifecycle, or publication is complete.

- Translate only the fields defined by the matching closed KOS command schema, retaining the validated adapter result as the source observation. Worktree commands accept the bounded observation fields, generic `effect reconcile` accepts its complete durable effect-result envelope, and `publication reconcile` accepts the successful push observation fields. Never submit an arbitrary raw adapter document or invent missing envelope fields.
- Preserve `dirty`, `mismatched`, conflicts, failures, and unknown outcomes. Never rewrite them into success or choose a workflow transition from them.
- A successful `push` result with `candidate_reachable: false` is an authoritative remote observation, not publication success. Reconcile it through the prepared publication protocol.
- `push` with `outcome: unknown` and `push_state_uncertain` means that a push may have reached the remote and cannot be submitted to `publication reconcile` without a concrete observation. Preserve the unresolved publication and enter its recovery protocol. A later `push` invocation is allowed only after authoritative recovery or adoption and all fresh authorization checks; its mandatory preflight observation returns without pushing when the candidate is already reachable or the base moved. Never blindly push again.
- After a timeout, lost response, transient failure, or otherwise invalid result from a mutating operation, treat the outcome as potentially uncertain. Return control to the operation's durable recovery protocol rather than creating a replacement intent or issuing an automatic retry.
- Do not repeat `materialize`, `remove`, `commit`, `fetch`, `rebase`, or `push` merely because the process failed, timed out, or returned `retryable: true`. A later invocation requires a fresh authoritative read, completed reconciliation when required, and renewed protocol authorization.
- A fresh worktree `observe` may be requested only when the current reservation protocol calls for it. It does not reconcile a generic effect or publication by itself.

## Safe Invocation Sequence

1. Read the task, attempt, and matching durable resource through `kos` in the immutable repository scope.
2. Verify lease ownership, fencing, current task version, resource state, and operation-specific preconditions; verify context digest and workflow allowlist for a workflow-requested effect.
3. Build one closed version 1 request entirely from current authoritative snapshots and verified effect inputs.
4. Invoke the installed adapter once with an argument array and separated output streams.
5. Validate the complete result, exit status, operation, outcome, and all applicable bindings.
6. Build the matching closed KOS reconciliation body from that validated observation and authoritative durable state; do not infer workflow success from adapter success.
7. Continue the workflow-step session only with the reconciled typed effect result authorized by the orchestrator.
