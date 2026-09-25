# Simplify Request-Bound Task Creation

## Goal

Replace the model-executed local creation protocol with a small idempotent
server and CLI operation.

## Scope

- Retain server-side uniqueness by project, task type, and creation key.
- Make repeating the same CLI creation request safe after a transport failure.
- Remove creation intents, receipts, locks, legacy namespaces, inode checks, and
  fsync procedures from agent instructions.
- Preserve existing tasks and creation keys.

## Out Of Scope

- General workflow or data-model simplification.
- Scheduler and step-agent rewrites beyond what is required by the new creation
  interface.

## Acceptance Criteria

- Repeating an identical request cannot create a duplicate task.
- Creation recovery requires no local protocol files.
- The CLI exposes one clear request-bound create-or-get operation.
- Existing keyed tasks remain recoverable.
- Concurrency and lost-response tests pass.
- `bin/check` passes.
