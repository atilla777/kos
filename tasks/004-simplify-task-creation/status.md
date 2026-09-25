# Status

State: done
Updated: 2026-09-25

## Completed

- Reviewed the existing keyed create-and-claim server, CLI, concurrency, and
  lost-response behavior.
- Chose a focused request-bound `create-or-get` operation that derives the
  canonical key and immutable task definition on the server.
- Added the server route and CLI command with exact-request canonicalization,
  scoped-key idempotency, and compatibility with existing keyed tasks.
- Replaced creation-file recovery tests with concurrency and dropped-response
  retry coverage.
- Removed `kos-create`, its installer inventory, and all creation intent, lock,
  receipt, inode, fsync, and legacy namespace instructions.
- Updated product, architecture, testing, installation, and CLI documentation.

## Current

Completed and verified.

## Next

Start task 005.

## Blockers

None.

## Verification

- `bin/check` passed: 232 tests, 2931 assertions, 0 failures, 0 errors.
- Independent review found one CR canonicalization edge case; it was fixed and
  covered before the final successful check.
