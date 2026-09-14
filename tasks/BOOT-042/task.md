---
id: BOOT-042
title: Reduce the full RSpec pre-push runtime below 90 seconds
status: completed
---

# Goal

Reduce the full local and pre-push RSpec runtime from 8 minutes 19 seconds to no more than 90 seconds on the current development machine without weakening runtime compatibility, timeout, persistence, concurrency, or isolation coverage.

# User Outcome

Developers receive full pre-push feedback in at most 90 seconds while production keeps its fixed 30-second retrospective budget and the serial suite remains available for diagnosis.

# Context

- The verified `BOOT-040` suite contains 723 examples and takes approximately 8 minutes 19 seconds serially.
- Three full OpenCode capability checks each exercise two real 30-second waits, contributing at least 180 seconds without adding proportional confidence.
- Concurrency and migration specs start many independent Rails processes; Git and OpenCode contracts also start many subprocesses.
- The test database currently has one fixed SQLite path, so unchanged process-level parallel execution would not be isolated.

# Requirements

- Keep the production retrospective timeout at 30 seconds.
- Verify the production timeout value independently from timeout behavior.
- Exercise timeout, cancellation, process termination, and primary-result preservation with injected test intervals between 0.01 and 0.1 seconds rather than production wall-clock waits.
- Do not make the production timeout configurable through an untrusted runtime environment variable merely to accelerate tests.
- Keep at least one real OpenCode 1.18.26 compatibility path.
- Remove redundant full capability executions while preserving installer and installed-copy wiring coverage through controlled verifier seams.
- Run parallel RSpec workers as isolated OS processes, not threads.
- Give every worker a distinct SQLite database and preserve the ordinary serial database path.
- Select a fixed worker count by measuring two and four workers; do not derive it automatically from CPU count.
- Keep `bundle exec rspec` available as the serial diagnostic command.
- Use the same normal test command in Mise, Lefthook pre-push, and CI.
- Preserve all user-visible KOS runtime behavior.

# Scope

- RSpec timing and process-isolation configuration.
- OpenCode launcher and capability-probe testability where needed to inject short probe budgets.
- Redundant real-runtime contract setup.
- Measured Rails, Git, CLI, or fixture startup optimizations needed to meet the target.
- Test infrastructure documentation and required dependency changes.

# Non-goals

- Changing the production 30-second retrospective budget.
- Reducing coverage by deleting reliability, compatibility, concurrency, or migration assertions.
- Thread-parallel RSpec execution.
- Optimizing application runtime performance unrelated to tests.
- Starting `BOOT-041` workflow publication work.

# Task-local Decisions

- The target is no more than 90 seconds on the current development machine.
- Short deterministic timing intervals prove timeout mechanics; a separate assertion proves the production value.
- Process workers are capped initially at four because examples themselves spawn Rails, Git, Node, Ruby, and OpenCode children.
- If process-heavy examples are unstable under parallel load, they may use a bounded serial lane while the remaining suite stays parallel.

# Acceptance Criteria

- All 723 baseline examples, plus any task-local coverage, execute exactly once in the full test command.
- No normal test waits multiple seconds solely to prove the 30-second retrospective contract.
- A real OpenCode 1.18.26 compatibility path remains covered.
- Serial and parallel suites pass without SQLite lock, missing-schema, shared-state, or parallel-only failures.
- The full pre-push RSpec command completes in no more than 90 seconds on the current machine.
- RuboCop, Brakeman, bundler-audit, and Zeitwerk checks pass.

# Implementation Plan

1. Record a serial per-example timing profile and confirm the dominant waits and subprocess costs.
2. Inject short, closed capability-probe timeout budgets while retaining a 30-second production default and direct contract assertions.
3. Consolidate or replace duplicate full capability executions with controlled verifier seams.
4. Add process-level RSpec parallelism and worker-specific SQLite paths.
5. Align Mise, Lefthook, and CI with the selected parallel command.
6. Measure two and four workers and select the fastest stable fixed count.
7. Optimize the remaining measured Rails, Git, CLI, or fixture startup bottlenecks only as needed to reach 90 seconds.
8. Run serial, repeated parallel, lint, security, and autoloading verification.
9. Record measured results, update the external plan, commit, and publish to `main`.

# Verification Plan

- `bundle exec rspec --profile`
- Focused specs for changed launcher, capability verifier, installer, and database configuration behavior.
- Full serial `bundle exec rspec` with a recorded seed.
- Full parallel runs with two and four workers and multiple seeds.
- The selected command through `mise run test` and Lefthook pre-push.
- `mise run check`
- `git diff --check`

# Risks

- Worker imbalance may hide theoretical parallel gains because a few files dominate runtime.
- Nested subprocess load can make four workers slower or less reliable than two.
- Incorrect SQLite suffixing could introduce cross-worker state or lock failures.
- Over-mocking capability verification could weaken installation compatibility evidence; retain one real pinned-runtime path and explicit wiring assertions.

# Implementation Result

- The capability verifier keeps the production invocation budget at 30 seconds but shortens only its private temporary child-plugin timer and injected launcher wait to 0.05 seconds.
- One real OpenCode 1.18.26 installer capability path remains and verifies child/root lifecycle behavior, exact custom-tool schema, restrictive agents, skill discovery, primary preservation, and timeout/failure independence.
- Redundant full runtime executions became fast schema and report contracts; installed-copy independence still performs real OpenCode skill and agent discovery after deleting the source bundle.
- Malformed authority has one real staged OpenCode rejection path, while identity, mode, enabled-tool, wildcard-authority, and retrospective-procedure policy variants are tested directly.
- `parallel_tests` 5.8.0 runs four isolated RSpec processes through `bin/parallel-spec`; every worker uses its own SQLite database selected by `TEST_ENV_NUMBER`.
- A checked-in static grouping keeps measured subprocess-heavy files balanced without generated timing logs. Mise, Lefthook, and CI all reach the same command.
- A shell-based descendant fixture removes a Ruby-startup race from the short process-group timeout test.
- No Rails/Git fixture-template refactor was needed because the measured four-worker result met the target with margin.

# Verification Result

- Baseline profile: `bundle exec rspec --profile 30` completed 723 examples in 8 minutes 20 seconds; five runtime examples consumed 322 seconds.
- Two-worker runtime-balanced measurement: 724 examples in 96 seconds.
- Four-worker runtime-balanced measurement: 724 examples in 54 seconds.
- Static clean-run grouping: 725 examples in 56 seconds without a generated runtime log.
- Final repeated static grouping: 726 examples in 65 seconds.
- Final serial `bundle exec rspec`, seed 60149: 726 examples, 0 failures in 3 minutes 17.5 seconds.
- `mise run check`: 726 examples, 0 failures in 66 seconds; 189 RuboCop files had no offenses; Brakeman reported no warnings; bundler-audit reported no vulnerabilities; Zeitwerk eager loading succeeded.
- `lefthook run pre-push --force`: 726 examples, 0 failures in 65.19 seconds.
- `git diff --check` passed.
- Final independent review reported no actionable findings.
