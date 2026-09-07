---
title: KOS Architecture Rules
status: active
---

# KOS Architecture Rules

## Source Of Truth

- KOS state is owned by the Rails application and persisted in SQLite.
- The Ruby CLI is the only programmatic interface for agents and skills to read or mutate KOS state.
- Agents, skills, scripts, and tests must not issue ad hoc SQL or edit the SQLite database directly.
- Database constraints protect invariants even when application validation is bypassed or concurrent processes race.

## Domain Boundaries

- Keep domain rules and state transitions in domain/application objects with explicit inputs and outputs.
- Keep controllers, CLI command parsing, serializers, Active Record callbacks, and job adapters thin. They translate I/O; they do not decide workflow policy.
- Keep persistence concerns in models and repositories. Do not make domain policy depend on Active Record callbacks or implicit database side effects.
- Keep Git, filesystem, process, network, and runtime-specific operations behind dedicated adapters. They return explicit results and errors to application services.
- Depend on interfaces at boundaries. Do not let domain objects know command-line syntax, worktree paths, environment variables, or Rails request objects.
- Do not add a general service layer by default. Extract an application object when an operation coordinates a domain decision with persistence or an external side effect.

## Adapter Safety

- Pass process arguments as an argument array. Never interpolate unvalidated agent or user input into a shell command.
- Validate repository-relative paths, remote URLs, ref names, and executable arguments before handing them to an adapter. Reject path traversal, symlinks outside the allowed root, and unapproved remotes.
- Provide adapters only the environment they need. Never write credentials or secret-bearing environment values to logs, artifacts, errors, or test fixtures.

## Reliability Boundaries

- A workflow transition, artifact registration, and validation of its contract must be one database transaction.
- External side effects are not transactional with SQLite. Persist an intent before the effect and reconcile observed state after interruption or an unknown result.
- Every mutating CLI command must be idempotent. Scope an idempotency key to the command and repository, store a request fingerprint with it, reject reuse with a different payload, and retain either its final result or a durable in-progress intent for reconciliation.
- Use optimistic locking for changed records and a lease with fencing token to own a workflow attempt before an external side effect. Check ownership atomically before recording each effect; use effect-specific preconditions, such as an expected remote OID for push, to make a stale attempt fail safely where the external system cannot enforce the token.
- Use database-enforced uniqueness for public task numbers, idempotency records, active worktree reservations, and other uniqueness invariants.
- Keep write transactions short. Handle SQLite contention only as a bounded transient retry; do not retry validation, conflict, or lost-lease failures as if they were transport errors.

## Git And Filesystem

- Only the repository adapter performs mutating Git operations, including worktree creation, commits, rebases, and pushes.
- A task that changes repository files uses its reserved branch and worktree. Validate repository identity, reservation, fencing token, and expected branch or commit before every Git side effect. A commit requires a verified expected diff and index; operations that do not create that diff require a clean worktree.
- Publish only the reviewed candidate SHA to the configured trusted remote and base ref using a fast-forward push. Immediately before push, atomically verify that the candidate, approved review evidence, required checks, task version, and expected base ref belong to the active attempt. Never force-push.
- Treat workflow bundles, artifacts, and review evidence as immutable. Reference repository files by repository-relative path plus commit and content digest.

## Change Decisions

- Add or update a domain specification for externally observable behavior.
- Add an ADR for decisions that affect multiple tasks or domains, architecture principles, data model, external contracts, or long-lived technical rationale.
- Prefer an explicit migration over an implicit data rewrite. Make migrations reversible when practical and test migration-sensitive behavior.
