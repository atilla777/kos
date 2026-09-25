# Status

State: done
Updated: 2026-09-25

## Current

Brief graphs now normalize, validate, digest, and materialize atomically under
the exact active publication fence. The validation route, CLI command, and
caller-provided digest are removed; complete graph observation remains available
for lost-response recovery.

## Checks

- Focused graph, API, CLI, package, scenario, matrix, profile, and skill tests:
  88 runs, 2,335 assertions, 0 failures.
- `bin/check`: 82 files inspected with no offenses; 240 runs, 3,201 assertions,
  0 failures.

## Next

Task 013 is active.

## Blockers

None.
