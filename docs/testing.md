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
- The PLAN-012 foundation test exercises one real `/kos` flow in OpenCode.
- Bootstrap tests prepare an empty database, rerun installation without
  duplicates, and prove a changed canonical definition creates a new immutable
  workflow revision without changing existing tasks.
- Migration tests assign deterministic non-reserved keys to existing types,
  preserve their workflow references, reject reserved-key collisions, and stop
  safely on partially migrated data.
- Request and CLI tests cover task type keys, filtered next-claim, exact claim,
  idempotent create-and-claim, owned and resumable observation, and atomic
  brief-child graph validation, creation, and observation.
- Concurrency tests prove filtered and exact claims retain the same ownership,
  blocker, and fencing guarantees as the original next-claim operation.
- OKF skill contract tests use temporary worktrees and prove concept discovery,
  metadata preservation, link and index maintenance, and confinement to
  `specs/`.
- Clean-install tests build the CLI gem and install the exact command, agent,
  and skill inventory into an isolated OpenCode configuration, removing known
  obsolete managed files and comparing installed bytes with the checkout.
- Step-artifact contract tests cover first creation, pre-dispatch removal on
  retry, direct writes independent of inode identity, unsafe object refusal,
  UTF-8 and template validation, exact outcome handling, unconfirmed-file
  cleanup, and exact-byte report recovery. They also preserve the separate
  atomic protocols for durable answer, intent, receipt, and graph files.

## Test Properties

- Tests must be deterministic and independent of execution order.
- Tests must not use the developer's real KOS database, repositories, or data
  directory.
- Time-sensitive ownership behavior must use controlled time.
- Failure cases and preserved invariants are tested alongside successful paths.
- External command ambiguity is tested through observed state, not assumptions
  about a previous command's response.
- Tests distinguish current implemented behavior from later target contracts;
  a normative document is not evidence that a command is available.

## Built-In Scenario Coverage

Automated tests must prove the development workflow follows `plan`,
`implement`, `document`, `review`, and `publish`; required project checks run
inside `implement`; and no built-in `check` transition occurs. A custom workflow
with a step ID of `check` remains valid.

Development scenarios cover type-filtered selection, read-only planning,
implementation failures corrected before transition, documentation before
review, independent review, `changes_requested` returning to `implement`,
`redesign_required` returning to `plan`, and `base_moved` repeating
implementation, documentation, and review.

Fix scenarios cover exact creation and claim by the `fix` key, read-only
evidence-based diagnosis, a regression check for the reproduced defect,
`needs_human` for ambiguous behavior or a non-reproducible report, and the same
post-diagnosis guarantees as development.

Brief scenarios cover execution in the main conversational agent, conformant
OKF output, independent read-only review, publication before materialization,
one-child and acyclic multi-child graphs, parent and blocker assignment, and
availability only after the parent completes. Batch validation failures create
no children and return to briefing before publication. Tests also cover
`changes_requested`, `base_moved`, `graph_invalid`, repeated materialization,
and contradictory graph conflicts.

Recovery tests interrupt brief materialization before response, compare the
complete observed child graph, and prove no duplicate or partial graph is
created. Existing recovery coverage remains required for creation, claim,
pause, report, moved base, commit, and push.

Artifact recovery tests require the orchestrator to remove a prior regular
`<step-id>.md` before each attempt and refuse symbolic links, directories, and
other unexpected objects without deleting them. They reject absent, empty,
partial, invalid-UTF-8, template-inconsistent, and outcome-inconsistent results.
An invalid or missing agent response cannot be reconstructed from the file, and
an ambiguous report may be repeated only after authoritative task observation
and byte-for-byte comparison with the previously verified artifact.

Creation recovery drops the `create-and-claim` response before and after commit
and proves a durable command intent plus unique owner returns the same task on
retry. Resume recovery covers zero, one, and multiple resumable tasks, active
takeover confirmation, exact question replay, atomic answer sidecars, and a
second interruption before the paused step advances.

API and CLI failure tests require stable errors for unknown or reserved type
keys, wrong projects, blocked or otherwise unclaimable tasks, owner collisions,
invalid and cyclic child definitions, repeated materialization, and a graph
whose supplied expected digest differs from its transactional canonical digest.
Command-skill tests require the orchestrator to reject reviewed-byte changes
before it sends a materialization request.

The final clean-install acceptance suite installs the CLI, commands, agents,
skills, and built-in catalog from one revision. Real `/kos-brief`, `/kos`, and
`/kos-fix` invocations must complete without hand-written workflow JSON,
numeric task type configuration, pre-publication commits, or manual lifecycle
commands. It verifies read-only `plan`, `diagnose`, and `review`, documentation
before review, all mandatory project checks, remote publication, final task
state, ownership release, and durable Markdown artifacts.

The deterministic installation, catalog, lifecycle, Git, and recovery layers
run in `bin/check`. Live OpenCode model execution is retained as release
acceptance evidence rather than placed in `bin/check`, so ordinary verification
does not depend on provider credentials, network availability, or model output.

## Commands

- `bin/test` runs the current automated test suite.
- `bin/lint` performs the non-mutating style check.
- `bin/format` applies automatic formatting fixes.
- `bin/check` prepares the test database, lints, and runs all tests required for
  a change.

Every completed change must leave `bin/check` passing.
