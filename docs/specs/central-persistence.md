---
title: KOS Central Persistence
status: active
---

# KOS Central Persistence

## State Layout

One Rails application owns one central state root. In production the root is `KOS_STATE_ROOT` when set to an absolute path, otherwise `$XDG_STATE_HOME/kos`, otherwise `~/.local/state/kos`. Startup fails before opening state when no absolute root can be resolved. Development and test may retain repository-local paths configured by their environments.

The production root has this logical layout:

```text
<state-root>/
  kos.sqlite3
  backups/
  locks/service.lock
```

`KOS_DATABASE_PATH` overrides the database path and must be absolute. KOS creates private state directories with mode `0700` and files with mode `0600`, subject to a more restrictive process umask, and refuses state paths that resolve through symlinks or to non-private existing objects.

The state root contains no bearer token, Git credential, repository checkout, task worktree, or runtime installation. Secrets remain process environment inputs. Repository checkouts and task worktrees remain at separately validated paths.

## Workflow Content

SQLite stores shared task types, workflow drafts, published workflow versions, instructions, templates, transitions, artifact contracts, installation-wide runtime settings, and durable repository-effect intents with the task and attempt state that consumes them. There is no separate workflow snapshot path or filesystem adapter.

Publishing a workflow validates and inserts its complete immutable version in one database transaction. Database constraints and triggers prevent update or deletion of a published version and its children. Activating that version changes only the task type's current-version reference. Task creation reads that reference and creates the task with its immutable `workflow_version_id` and initial state in one short transaction.

Workflow drafts are mutable and use optimistic locking. A draft is never executable and a task never references it. The canonical published content, including Markdown instructions and templates, is included in normal SQLite-consistent backup and recovery.

## Database Ownership

Only Rails persistence code opens SQLite. Active Record models and focused persistence repositories own rows, associations, constraints, and query behavior. Domain and application objects receive explicit values and persistence interfaces; they do not issue SQL, depend on Active Record callbacks for workflow policy, or know database paths. Controllers and serializers translate the versioned API contract and do not coordinate persistence policy.

Git discovery and reads remain behind the repository adapter; mutating Git remains exclusively owned by `kos-repository` as defined by [Repository Isolation](repository-isolation.md). Workflow catalog operations do not read target-repository files.

Every repository-owned row carries immutable `repository_id`, and repository-local uniqueness constraints include that scope. Repository task prefixes are globally unique, while numeric task sequences are repository-local. Global records, including repository registrations and the registration idempotency scope, are explicitly global rather than represented by a fabricated repository identifier. Database constraints, transactions, locking, and entity-specific columns are introduced by their assigned persistence tasks.

## Production Migrations

Rails migrations are the only supported schema-change mechanism. The operator stops the API and runs the idempotent `RAILS_ENV=production bin/rails kos:state:prepare` operation before starting a new release. The operation resolves and validates state paths, obtains the exclusive `locks/service.lock`, creates the database when absent, and applies all pending migrations. The production API holds that same lock for its lifetime and refuses startup when it cannot obtain it or when migrations are pending. Normal API startup never applies DDL.

Before applying one or more migrations to an existing database, the prepare operation creates a SQLite-consistent backup through the Rails persistence boundary under `backups/`. Copying the database file directly while WAL may contain committed pages is not a valid backup. A backup is durably written before the first schema change and records its source schema version, creation time, byte size, and SHA-256 digest in a sidecar manifest. Backup retention and deletion are explicit operator actions and are not automatic in version 1.

Migrations are forward-only in normal production operation, safe for existing rows, and transactional where SQLite supports the operation. Data backfills use migration-local SQL or classes rather than current application models. A migration failure leaves the service stopped and reports the last applied version without deleting the pre-migration backup. Recovery restores the complete backup while the service is stopped, verifies its digest and SQLite integrity, and then either runs the previous compatible KOS release or retries a corrected forward migration. Automatic destructive rollback and startup with a database newer than the running release are prohibited.

## Repository Registration

Repository registration is an authenticated but unscoped operation because no `repository_id` exists yet. Its machine command is:

```text
kos repository register --input <path|-> --idempotency-key <key> --json
```

It maps to `POST /api/v1/repositories` and does not accept `--repository`. The input contains `git_common_dir`, `task_prefix`, `trusted_remote`, `trusted_remote_url`, and full `base_ref`. `git_common_dir` is an absolute, already canonical path. `task_prefix` is 2 through 10 uppercase ASCII letters or digits beginning with a letter; lowercase input is invalid rather than normalized. The normalized URL is an absolute `https`, `ssh`, `git`, or `file` URI without a password, query, or fragment; an SSH username is allowed, and scp-like Git syntax is presented and submitted in equivalent `ssh://` form. The base ref is under `refs/heads/`.

Before calling this command, `kos-initialize` obtains and displays the human-selected task prefix together with the discovered canonical Git common directory, trusted remote name, normalized URL, and full base ref. It requires explicit human confirmation of those exact values. Automatic selection of `main` or `master` does not count as confirmation.

The API validates the task-prefix syntax and global availability. It resolves the path without following a caller-selected identity assertion, verifies that it is a Git common directory, asks the repository adapter for the configured remote URL and base ref, normalizes those observed values independently, and compares them with the request. An invalid prefix, missing or non-canonical common directory, missing remote or base ref, URL containing credentials, or mismatch with observed Git state returns `repository_registration_invalid` with safe details. The request path is never sufficient proof by itself.

The canonical Git common directory is globally unique among active registrations, and a task prefix is never reused within the lifetime of the central state. Remote URL is not unique: separate clones may be registered separately. A first valid registration creates and returns a repository resource with an immutable UUID and task prefix. A later call with another idempotency key and the same canonical common directory returns that existing resource when task prefix, trusted remote name, normalized URL, and base ref all agree. If the prefix or any trust setting differs, it returns `repository_registration_conflict` and changes nothing. A different repository requesting an occupied or previously used prefix receives the same conflict. Moving a checkout or changing its prefix or trust settings requires a future explicit rebind or update contract; registration never performs that update implicitly.

`repository.register` always returns HTTP `200`, including creation, matching repeat, and completed idempotency replay, so callers do not infer durable identity from transport status. Its idempotency records use the global scope and the normal canonical request fingerprint with the scope component represented by the literal `global`. Workflow-catalog and runtime-configuration mutations use that same explicit global scope; task execution remains repository-scoped. A matching key and fingerprint replays the original resource; reuse with different input returns `idempotency_conflict`.

[ADR-0005](../decisions/0005-central-persistence-and-registration.md) records the architecture decision behind central state and registration. [ADR-0006](../decisions/0006-repository-task-prefixes.md) records the public-number namespace decision. [ADR-0007](../decisions/0007-central-workflow-catalog.md) records central workflow-content ownership.
