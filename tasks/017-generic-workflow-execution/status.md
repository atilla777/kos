# Status

State: done
Updated: 2026-09-26

## Current

Made workflow context authoritative for execution mode, model tier, and
substantive step instructions. Main steps execute in the command agent;
subagent steps use one of two generic tier profiles. Added CLI-owned session
IDs, protected reserved task-type workflows, removed role-specific assets and
name-based Git policy, preserved older immutable workflow revisions through
effective defaults, and updated installation cleanup and contracts.

## Blockers

None.

## Checks

- Independent read-only review: no remaining actionable findings after fixes
- `git diff --check`: passed
- `bin/check`: 84 lint files, no offenses; 248 runs, 3797 assertions,
  0 failures, 0 errors, 0 skips
