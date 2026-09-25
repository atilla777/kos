---
name: kos-cli
description: Use for discovering and safely invoking the public KOS CLI, interpreting its results, and recovering ambiguous operations.
---

# KOS CLI

## Role And Configuration

Use only the executable at the absolute administrator-configured
`KOS_CLI_PATH`. Do not substitute an ambient `kos`, repository executable,
direct HTTP request, Rails command, or SQLite access. Stop as `blocked` when the
configured executable is unavailable or incompatible.

`KOS_API_URL` selects the server and otherwise defaults to the CLI's local URL.
`KOS_API_TOKEN` is required except for `health`. Never print the token, put it in
process arguments, or embed it in a URL. It is a shared bearer credential whose
holders are fully trusted for every application operation; owner IDs, leases,
and claim-version fences provide concurrency consistency, not authorization.

## Discover And Invoke

Run `--version` and top-level `--help` to identify the installed CLI. Before an
operation's first use, read its `--help`. The executable's help is the
authoritative command and option reference; do not reconstruct syntax from this
skill. A required operation missing from help is incompatible and `blocked`,
not permission to emulate it through another interface.

Pass every value as a distinct process argument. Never interpolate task text,
Markdown, JSON, paths, identifiers, or credentials into shell syntax. Where
help permits `-` as a file value, prefer standard input for exact structured
content. Never use a repository-local task artifact, sidecar, or receipt as KOS
protocol state.

## Project Discovery

Accept only the canonical repository identity derived by `kos-git`. Use the
public project lookup operation and require its returned identity to equal that
value exactly. Missing or mismatched registration stops before mutation. Never
normalize the lookup value again, accept a near match, infer a project ID, or
create a registration as recovery.

## Results

- Exit `0` means the HTTP operation succeeded. The unchanged server body is on
  standard output and may be empty for a no-content response.
- Exit `1` means an HTTP failure. Preserve the unchanged server body from
  standard output.
- Exit `2` means a usage, configuration, or local-input failure. Read the JSON
  error from standard error.
- Exit `3` means a transport failure. Read the JSON error from standard error.

For a successful JSON operation, parse the complete response and require the
fields needed for the current decision. Malformed, missing, or contradictory
required state is `blocked`; do not invent defaults. Preserve server and CLI
errors without reinterpreting them as workflow outcomes.

## Ambiguous Operations

Reads may be repeated. Never infer that a mutation failed only because its
response was lost. Observe authoritative state before retrying. Retry a mutation
only when help or the server contract makes it idempotent, or observation proves
it did not occur and the same fenced input remains valid. `task create-or-get`
allows one identical retry because the server enforces request identity. If
success or a safe retry cannot be established, stop as `blocked`.

Do not expose administrative project/workflow/task-type operations, task
creation, claim, takeover, resume, cancellation, graph mutation, or arbitrary
CLI execution to a step profile unless that profile's explicit authority
requires the exact focused operation. The shared bearer token is the
authorization boundary; owner and fence checks prevent conflicting trusted
operations but do not authorize agents independently.
