# Simplified Live Acceptance Evidence

Date: 2026-09-25

## Environment

- The isolated rerun used KOS commit `5bcb29ff3d82d86d74fbf87515201cc4a5139dd1`,
  CLI version 0.1.0, a clean KOS database, a fixture checkout, publisher
  worktrees, an independent observer checkout, and a bare fixture remote.
- `installed-inventory.txt` records 9 agents, 3 commands, and 6 skills. There is
  no `kos-verify` agent.
- `cli-help.txt` retains version, top-level help, and both child-graph command
  help responses. It exposes `materialize-children` and `children`, but no
  `validate-children` command.
- No token, credential, log, transcript, session identifier, or home path is
  retained.
- `timings.txt` records wall-clock times for all three scheduler sessions. The
  development run includes a 3-hour 22-minute API interruption; active elapsed
  time across the three scenarios was 44 minutes 59 seconds.

## Server State

- `task-{1,2,3}-context.json` are pretty-printed public CLI responses. Every task
  is `completed` at `publish` with null owner and lease.
- The retained accepted artifacts are task 1 `brief`, `review`, and `publish`;
  task 2 `review` and `publish`; and task 3 `review` and `publish`.
- Task 2's context records `required_checks: passed` and two reviewed commits.
  Task 3's context records a reproduced diagnosis, `required_checks: passed`,
  review, and publication.

## Remote Evidence

`fixture-remote.bundle` is a complete, self-contained copy of the observed
remote history. `verify_evidence.rb` clones that bundle and parses the accepted
review JSON rather than trusting this summary. It independently verifies:

- remote ancestry and each review's exact ordered SHA sequence;
- every commit's one parent, tree, and exact raw canonical `KOS-Task: ID`
  trailer;
- exact changed paths; and
- SHA-256 of the complete `git diff --binary --no-ext-diff --no-textconv`
  output.

The accepted and independently observed sequences are:

- task 1: base `9bd261e119da5ee170c222ab8c8743f2de1155dc`, commit/tip
  `07154f11ecbaf731b0c594f48701d9ac88c271ee`, digest
  `f38facd08abfcc666fab81e453f19190825a8fef3fa97e3675ec06fb2a209381`;
- task 2: base `07154f11ecbaf731b0c594f48701d9ac88c271ee`, commits
  `219952f6ca34bfcdae4ed302bf2c9d776def81f2` and
  `1658387a16682011e2749580be56bda8cfaf4a2f`, digest
  `ef4b6ed17e8e554498b52c309ad004f8b05fbd92f5baa8f699cebf4da57702be`;
- task 3: base `9c9b0783756e994ff330383399aecc4b688939db`, commit/tip
  `3a499d3a2ac5a92caae4e42a58d6e3b8dbb368ef`, digest
  `640aa8782eedea90e3f2c40dfbdba663e1cec0ca6981f57f07ccdee8ec6bd8a5`.

The remote history also contains the deliberate unowned regression commit
`9c9b0783756e994ff330383399aecc4b688939db` between tasks 2 and 3.

## Brief Graph

`brief-graph-definition.json` retains the exact materialization definition
derived verbatim from the accepted brief. The verifier checks those exact title,
description, type, and blocker requirements against the accepted brief/review
and `task-1-children.json`. It independently canonicalizes the definition and
recomputes digest
`sha256:6926b2f25ed3f0e126c2b80c3cbde1c16773da77e5c7e95dcde4466dee4d30cd`.
The observed graph has exactly task 2, with task 1 as its parent and only
blocker, and no sibling blockers.

## Launches And Checks

- `agent-launches.json` is the sanitized profile/prompt-only projection of the
  three scheduler sessions. It covers every completed workflow through
  publication, records the interrupted and permission-denied attempts, and
  contains no verifier launch. The clean installed inventory also has no
  verifier profile that any scheduler could launch.
- `verification-output.txt` records every passing deterministic evidence check.
- `fixture-check.txt` records the independent observer at fetched remote `main`:
  3 runs, 23 assertions, 0 failures, 0 errors, 0 skips.
- The fixture remote passed `git fsck --strict`; the retained bundle passed
  `git bundle verify` and records complete history.
- KOS `bin/check` passed; its exact result is recorded in `kos-check.txt`.

## Follow-Up Observation

`argument-observation.json` preserves the exact operator-intended request bytes,
their digest, and the persisted submitted bytes independently extracted from
task 1 context. The persisted value is exactly one leading and trailing `0x22`
byte around the expected 550-byte payload. Task 015 owns reproducing and fixing
that command-expansion boundary; it did not affect publication acceptance.
