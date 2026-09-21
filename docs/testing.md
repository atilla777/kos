# Testing Rules

## Required Layers

- Unit tests cover domain validation and pure behavior.
- Request or integration tests cover REST contracts and persistence effects.
- Concurrency tests cover claims, claim fencing, and atomic transitions.
- CLI tests execute the public command rather than internal implementation.
- Gem packaging tests build and install the CLI into an isolated gem home.
- Git integration tests use temporary repositories and a temporary bare remote.
- Recovery scenarios use isolated persistent databases, data directories, and
  subprocesses; they never inherit an ambient database URL or Git configuration.
- Moved-base scenarios prove checks and read-only review repeat while staged,
  unstaged, and untracked task work remains uncommitted.
- The final acceptance test exercises a real `/kos` flow in OpenCode.

## Test Properties

- Tests must be deterministic and independent of execution order.
- Tests must not use the developer's real KOS database, repositories, or data
  directory.
- Time-sensitive ownership behavior must use controlled time.
- Failure cases and preserved invariants are tested alongside successful paths.
- External command ambiguity is tested through observed state, not assumptions
  about a previous command's response.

## Commands

- `bin/test` runs the current automated test suite.
- `bin/lint` performs the non-mutating style check.
- `bin/format` applies automatic formatting fixes.
- `bin/check` prepares the test database, lints, and runs all tests required for
  a change.

Every completed change must leave `bin/check` passing.
