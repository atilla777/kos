# Materialize Brief Graphs Atomically

## Goal

Remove the separate brief graph validation handshake and validate each reviewed
graph inside its fenced atomic materialization operation.

## Scope

- Remove `validate-children` from the API and CLI.
- Remove the caller-provided expected digest.
- Validate, normalize, digest, and create the full graph in one transaction.
- Preserve graph observation for lost-response recovery.

## Acceptance Criteria

- Invalid graphs create no partial state.
- Materialization requires the exact active publication fence.
- A lost response is recoverable through child-graph observation.
- Public help and documentation contain no validation handshake.
- `bin/check` passes.
