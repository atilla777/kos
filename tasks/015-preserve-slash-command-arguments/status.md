# Status

State: done
Updated: 2026-09-25

## Current

Accepted the task 014 discrepancy as an OpenCode 1.18.26 CLI limitation rather
than an upstream blocker or a KOS unquoting heuristic. Live evidence shows one
argv containing spaces is display-serialized with wrapper quotes and escaped
literal quotes before `$ARGUMENTS`, while separate argv words produce the exact
plain multiword request. KOS preserves the expansion through scheduler, CLI,
server hashing, persistence, and idempotent creation. Documentation identifies
interactive slash payloads and separate `opencode run --command ...` argv words
as supported exact paths. Deterministic tests begin honestly after expansion and
cover command framing, scheduler-to-fake-CLI stdin, packaged CLI transport, and
server persistence, creation keys, and idempotence.

## Blockers

None. The OpenCode 1.18.26 limitation is explicitly accepted.

## Checks

- isolated OpenCode 1.18.26 sentinel reproduction: eight independent sessions;
  four exact argv/expansion cases and sanitized per-run bytes retained
- `ruby tasks/015-preserve-slash-command-arguments/artifacts/verify_sentinel_evidence.rb`:
  verified 4 argv/expansion cases, 8 runs, and 4 byte-identical pairs
- focused tests: 71 runs, 1114 assertions, 0 failures, 0 errors, 0 skips
- `bin/check`: 244 runs, 3807 assertions, 0 failures, 0 errors, 0 skips;
  85 lint files, no offenses
