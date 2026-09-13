---
title: KOS Architecture Rules
status: active
---

# KOS Architecture Rules

## Source Of Truth

- KOS state is owned by the central Rails application and persisted in one SQLite database.
- The Rails application may serve multiple Git repositories. Every repository-owned record and operation must be scoped by an immutable repository identifier.
- The Ruby CLI is the only agent-facing programmatic interface to KOS state. It reads and mutates state through the versioned Rails REST API and must not load Rails models or persistence code.
- Only Rails persistence code may access SQLite. Agents, skills, the CLI, scripts, and tests outside the persistence boundary must not issue ad hoc SQL or edit the database directly.
- Rails persistence owns shared workflow drafts and published workflow versions. Published versions and their execution content are immutable and tasks reference them by foreign key.
- Database constraints protect invariants even when application validation is bypassed or concurrent processes race.

## API Boundary

- Expose the machine API under a versioned namespace such as `/api/v1`. Keep its JSON request, response, and error contracts explicit and covered by contract tests.
- Keep every CLI command non-interactive with structured JSON output. Reserve stdout for the versioned machine response and stderr for diagnostics.
- Bind the local service to loopback by default and require a bearer token for every API endpoint except health checks. Never persist or log the token in the repository.
- Resolve a repository at the API boundary and pass its immutable identifier explicitly into application operations. Never infer repository scope from process-global state or an untrusted path alone.
- Keep controllers and serializers as transport adapters. Authentication, JSON parsing, and HTTP status mapping belong at this boundary; workflow policy does not.

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
- Every mutating CLI command and corresponding API operation must be idempotent. Scope an idempotency key to the command and either its repository or the explicit global catalog/configuration scope, store a request fingerprint with it, reject reuse with a different payload, and retain either its final result or a durable in-progress intent for reconciliation.
- Global catalog and configuration operations, including repository registration before a repository identifier exists, never invent a repository identifier solely to satisfy scoping.
- Use optimistic locking for changed records and a lease with fencing token to own a workflow attempt before an external side effect. Check ownership atomically before recording each effect; use effect-specific preconditions, such as an expected remote OID for push, to make a stale attempt fail safely where the external system cannot enforce the token.
- Use database-enforced uniqueness for public task numbers, idempotency records, active worktree reservations, and other uniqueness invariants.
- Enable SQLite foreign keys and WAL, choose an explicit durable synchronous policy and busy timeout, and keep write transactions short. Handle contention only as a bounded transient retry with the original idempotency key; do not retry validation, conflict, or lost-lease failures as if they were transport errors.

## Git And Filesystem

- Only the repository adapter performs mutating Git operations, including worktree creation, commits, rebases, and pushes.
- A task that changes repository files uses its reserved branch and worktree. Validate repository identity, reservation, fencing token, and expected branch or commit before every Git side effect. A commit requires a verified expected diff and index; operations that do not create that diff require a clean worktree.
- Publish only the reviewed candidate SHA to the configured trusted remote and base ref using a fast-forward push. Immediately before invoking the repository adapter, atomically verify that the candidate, approved review evidence, required checks, task version, prepared publication, and expected base ref belong to the active attempt. The adapter must independently enforce the exact expected remote OID and fast-forward relation; never authorize a non-fast-forward update.
- Treat published workflow versions, artifacts, and review evidence as immutable. Reference repository files by repository-relative path plus commit and content digest.
- Keep runtime installations derived from canonical `skills/` sources. Materialize files through staging and atomic rename; do not treat runtime copies as editable sources.

## Change Decisions

- Add or update a domain specification for externally observable behavior.
- Add an ADR for decisions that affect multiple tasks or domains, architecture principles, data model, external contracts, or long-lived technical rationale.
- Prefer an explicit migration over an implicit data rewrite. Make migrations reversible when practical and test migration-sensitive behavior.
