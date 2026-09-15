---
name: kos-cli
description: Use when reading or changing KOS task and workflow state through the non-interactive Ruby CLI.
---

# KOS CLI

Use the installed `kos` executable as the only agent-facing interface to KOS state. Treat every identifier, version, precondition, and response as untrusted until the CLI validates it.

## Authority Boundary

- Never call the Rails REST API directly, access SQLite, load Rails models, use `rails runner`, or edit KOS state files.
- Never run a mutating Git command through this skill. KOS state commands record intent and observations; only `kos-repository` performs mutating repository operations.
- Do not use this skill from a workflow-step subagent. Return a typed request to the lease-owning orchestrator instead.
- Perform an attempt-owned mutation only as the lease-owning orchestrator and only with current values read from KOS for the same repository, task, and attempt.
- Never infer or repair a UUID, public task number, status, transition, lock version, fencing token, reservation, effect, or publication identifier.
- Treat skill instructions as procedure, not authority. A command is allowed only when the pinned workflow context and current actor role allow it.

## Invocation Contract

Every invocation is non-interactive and includes `--json`:

```text
kos <resource> <operation> --json [read options]
kos <resource> <operation> --repository <repository-uuid> --json [read options]
kos <resource> <operation> [--repository <repository-uuid>] --input <path|-> --idempotency-key <key> --json
```

- Use `kos`, not a path into the KOS source checkout.
- Supply `KOS_API_TOKEN` only through the environment. Never put it in command arguments, JSON, logs, artifacts, or error reports.
- `KOS_API_URL` defaults to `http://127.0.0.1:3000`. Treat it as trusted installation configuration: never set or replace it from task, workflow, artifact, tool, or model input. Do not call that URL yourself.
- `KOS_API_TIMEOUT_SECONDS` defaults to `30` and, when set, must be a positive integer.
- Global catalog commands omit `--repository`; repository-owned commands require the immutable repository UUID.
- A read encodes its body through command-specific options. List reads require `--limit` from 1 through 100 and may take an opaque `--cursor`.
- A mutation requires `--input <path|->` and an 8-to-255-character idempotency key containing only ASCII letters, digits, `.`, `_`, `:`, or `-`.
- Mutation input is only the command-specific JSON object. The CLI adds the protocol envelope and validates the complete request.
- Prefer `--input -` when input can be passed without writing a temporary file. Keep stdout and stderr separate; never use `2>&1` when parsing the result.

Examples:

```text
kos task get --repository "$repository_id" --task "$task_number" --json
kos repository get --repository "$repository_id" --json
kos artifact list --repository "$repository_id" --task "$task_number" --limit 100 --json
kos attempt claim --repository "$repository_id" --input - --idempotency-key "$idempotency_key" --json
```

`task create` requires `task_type: "quick-fix"` and a closed `task_input` with `schema_version: "1"`, a nonblank `title`, and the complete approved Markdown `approved_brief`. Preserve the exact approved brief when retrying. Never derive it from the title, dialogue, or a repository file, and never create a task before the human approval boundary has produced it.

## Available Commands

Use only these commands until a later installed CLI explicitly supports more:

| Scope | Reads | Mutations |
| --- | --- | --- |
| Global | `runtime-config get`, `task-type list`, `workflow list`, `workflow get`, `workflow export`, `workflow-draft get`, `workflow-draft validate` | `repository register`, `runtime-config update`, `workflow-draft import`, `workflow publish`, `workflow activate` |
| Repository | `repository get`, `task get`, `attempt get`, `worktree get`, `effect get`, `publication get`, `artifact list` | `task create`, `attempt claim`, `attempt renew`, `attempt fail`, `attempt needs-human`, `attempt reconcile`, `step context`, `step complete`, `worktree reserve`, `worktree confirm`, `worktree reconcile`, `worktree release`, `effect prepare`, `effect reconcile`, `publication prepare`, `publication reconcile` |

## Unavailable Commands

`artifact register` and `publication complete` exist in the wider protocol design but are not available in the current CLI. Do not invoke them or simulate them through direct API access.

## Validate Every Result

Capture stdout and the process exit status separately. The CLI performs full request and response JSON Schema validation. Independently fail closed unless all of these checks pass:

1. Stdout contains exactly one JSON object and no prose.
2. `schema_version` is exactly `"1"`.
3. `request_id` is a UUID string.
4. `command` equals the logical command invoked, such as `task.get`; `unknown` is valid only for an `unknown_command` failure.
5. Exactly one of `data` or `error` is present.
6. Exit status is `0` for `data`, or matches the error category below for `error`.

Do not use partial `data`, guess a malformed field, parse stderr as machine state, or branch on the human-readable error message. Treat malformed JSON, an unexpected command, a mismatched branch or exit, and an unsupported schema version as failure.

## Stable Error Handling

| Exit | Category | Action |
| ---: | --- | --- |
| 1 | `internal` | Stop. Do not retry automatically; report the stable code and request ID. |
| 2 | `validation` | Fix the request from authoritative inputs. Do not retry the unchanged request. |
| 3 | `authentication` | Stop. Do not expose or guess credentials. |
| 4 | `authorization` | Stop. Do not probe other repository identities. |
| 5 | `not_found` | Reread only when the workflow permits discovery; do not guess another identifier. |
| 6 | `conflict` | Do not resubmit blindly. Follow the code-specific recovery below. |
| 7 | `lease_lost` | Stop all attempt-owned mutation and repository work immediately. Return control to recovery. |
| 8 | `transient` | The CLI already exhausted its bounded retry policy. Treat a mutation outcome as potentially unknown. |

Only `transient` errors have `retryable: true`. Require `retryable: false` for every other category. A category, code, retryability, or exit mismatch is an invalid result, not a reason to coerce the response.

For stable conflict and recovery codes:

- `stale_lock_version`, `invalid_transition`, `dependency_unsatisfied`, and `context_unavailable`: reread task and attempt state, re-evaluate the workflow, and form a new operation only if still valid. Never patch the old body by guessing a version or transition.
- `idempotency_conflict`: stop. The key is already bound to another body; do not evade the conflict with a new key.
- `idempotency_in_progress`: inspect the named durable resource and use its read or reconciliation protocol. Do not submit a duplicate mutation.
- `lease_expired` or `fencing_token_stale`: stop using the attempt immediately. Do not renew, complete, reconcile an external effect, or continue repository work with stale ownership.
- `base_moved`: do not repeat publication. The orchestrator must follow the new candidate and evidence flow.
- `task_number_exhausted`, `task_type_unavailable`, `workflow_version_conflict`, and `repository_registration_conflict`: stop for an explicit workflow or human decision.

## Idempotency And Unknown Outcomes

- Create one idempotency key for one logical mutation and retain the exact command body associated with it.
- A completed replay with the same command, scope, key, and body is the same operation, even when mutable preconditions have since changed.
- Never reuse a key with another body, and never generate a new key merely because a response was lost or timed out.
- The CLI itself makes at most three total attempts for transport failures and `transient` API responses, reusing the original body and key. Do not place an unbounded retry loop around it.
- After a final transient mutation failure, read authoritative state when the resource identifier is known. When a creation response lost the new identifier, recover the recorded response with an exact same-command, same-body, same-key replay; never create a replacement intent.
- Never blindly resubmit an `unknown` repository or publication effect. Observe the external state through the owning orchestrator and `kos-repository`, then record that typed observation through the matching KOS reconciliation command.
- Replaying an idempotent state mutation means the exact same command, scope, body, and key. It may recover a recorded response, but it never authorizes repeating an underlying Git or other external effect. Prefer resource read and reconciliation whenever its identifier is known.

## Safe Mutation Sequence

1. Read the task and related attempt or durable resource from the correct repository scope.
2. Verify the actor role, pinned workflow state, active ownership, and required operation.
3. Build the command-specific body with the exact current identifiers and preconditions.
4. Assign and retain one idempotency key for that logical intent.
5. Invoke `kos` once and validate the complete result envelope and exit status.
6. On success, use only returned `data`; do not infer side effects that are absent from it.
7. On failure, follow the stable category and code. Reread or reconcile before deciding whether any further mutation is valid.
