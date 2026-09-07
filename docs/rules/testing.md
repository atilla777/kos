---
title: KOS Testing Rules
status: active
---

# KOS Testing Rules

## Required Coverage

- Add or update an automated test for every behavior change and bug fix.
- Unit-test domain rules, workflow transitions, artifact contracts, bundle pinning, and locking decisions when they are added or changed.
- Integration-test CLI commands, persistence, migrations, idempotency, and error contracts when they are added or changed.
- End-to-end test task execution across worktree allocation, candidate creation, review, and publication when a change crosses those boundaries.
- Add contract tests when changing workflow YAML, instructions, templates, CLI JSON schemas, or runtime adapters.

## Reliability Cases

- Test the successful path and failures that can violate a state, security, publication, or recovery invariant. Document a consciously untested failure when its simulation is disproportionate to the change.
- Cover concurrent claims, stale lock versions, expired leases, stale fencing tokens, duplicate idempotency keys, and SQLite contention when changing the relevant persistence or workflow boundary.
- Use controlled fakes or test repositories for Git and remote interactions. Do not make the normal test suite depend on a network service or a developer's global Git configuration.
- Add fault-injection coverage when changing a path that crosses a durable intent, a Git side effect, and persistence of its observed result.
- Reproduce a reported defect with a failing test before fixing it when practical.

## Running Tests

- Run the smallest relevant test set while iterating, then run the affected suite before completion.
- Run the full suite for changes to shared infrastructure, persistence, workflow semantics, CLI contracts, or repository adapters.
- State exactly which commands ran and whether any required check could not run.
- Tests must be deterministic, isolated, and safe to run repeatedly in any order.
