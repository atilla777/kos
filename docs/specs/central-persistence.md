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
  workflow-snapshots/
    sha256/<first-two-hex>/<remaining-hex>/
      manifest.json
      members/.kos/...
    .staging/<uuid>/
  backups/
  locks/service.lock
```

`KOS_DATABASE_PATH` overrides the database path and `KOS_SNAPSHOT_ROOT` overrides `workflow-snapshots`; each override must be absolute. Snapshot staging must remain on the snapshot root's filesystem so final placement can use atomic rename. KOS creates private state directories with mode `0700` and files with mode `0600`, subject to a more restrictive process umask, and refuses state paths that resolve through symlinks or to non-private existing objects.

The state root contains no bearer token, Git credential, repository checkout, task worktree, or runtime installation. Secrets remain process environment inputs. Repository checkouts and task worktrees remain at separately validated paths.

## Workflow Snapshot Store

The Rails workflow snapshot adapter is the sole owner of snapshot paths. A bundle directory is addressed by the 64 lowercase hexadecimal characters from its canonical `sha256:` bundle digest. It contains the RFC 8785 canonical manifest as `manifest.json` and each exact member byte sequence under `members/<repository-relative-member-path>`. Paths and bytes must satisfy the [Project Configuration](project-configuration.md) contract.

Snapshot materialization is idempotent:

1. Read and validate the authoritative project configuration through the repository read adapter.
2. Write the complete candidate snapshot to a unique staging directory on the snapshot filesystem.
3. Re-read and verify every staged member, manifest, member digest, and aggregate bundle digest; durably flush files and directories.
4. Atomically rename the staged directory to its digest-addressed final path and durably flush the parent directory.
5. If the final path already exists, verify it byte-for-byte against the digest and use it instead of replacing it.
6. Only after a complete final snapshot exists, create the task and its snapshot reference in one short database transaction.

A failed or interrupted materialization never creates a database reference to an incomplete bundle. Stale staging directories and complete but unreferenced bundles may be reconciled later, but KOS does not remove a referenced bundle or infer safety from age alone. A mismatch at an existing digest path is `bundle_inconsistent`, not an overwrite opportunity.

The API, CLI, orchestrators, and runtime skills never receive the state root or snapshot paths. They receive only schema-defined verified content, identifiers, and digests.

## Database Ownership

Only Rails persistence code opens SQLite. Active Record models and focused persistence repositories own rows, associations, constraints, and query behavior. Domain and application objects receive explicit values and persistence interfaces; they do not issue SQL, depend on Active Record callbacks for workflow policy, or know database and snapshot paths. Controllers and serializers translate the versioned API contract and do not coordinate persistence policy.

An application operation coordinates database state with a repository or snapshot adapter when required. The snapshot adapter is a narrow filesystem boundary, not a replaceable general storage backend. Git discovery and reads remain behind the repository adapter; mutating Git remains exclusively owned by `kos-repository` as defined by [Repository Isolation](repository-isolation.md).

Every repository-owned row carries immutable `repository_id`, and repository-local uniqueness constraints include that scope. Global records, including repository registrations and the registration idempotency scope, are explicitly global rather than represented by a fabricated repository identifier. Database constraints, transactions, locking, and entity-specific columns are introduced by their assigned persistence tasks.

## Production Migrations

Rails migrations are the only supported schema-change mechanism. The operator stops the API and runs the idempotent `RAILS_ENV=production bin/rails kos:state:prepare` operation before starting a new release. The operation resolves and validates state paths, obtains the exclusive `locks/service.lock`, creates the database when absent, and applies all pending migrations. The production API holds that same lock for its lifetime and refuses startup when it cannot obtain it or when migrations are pending. Normal API startup never applies DDL.

Before applying one or more migrations to an existing database, the prepare operation creates a SQLite-consistent backup through the Rails persistence boundary under `backups/`. Copying the database file directly while WAL may contain committed pages is not a valid backup. A backup is durably written before the first schema change and records its source schema version, creation time, byte size, and SHA-256 digest in a sidecar manifest. Backup retention and deletion are explicit operator actions and are not automatic in version 1.

Migrations are forward-only in normal production operation, safe for existing rows, and transactional where SQLite supports the operation. Data backfills use migration-local SQL or classes rather than current application models. A migration failure leaves the service stopped and reports the last applied version without deleting the pre-migration backup. Recovery restores the complete backup while the service is stopped, verifies its digest and SQLite integrity, and then either runs the previous compatible KOS release or retries a corrected forward migration. Automatic destructive rollback and startup with a database newer than the running release are prohibited.

## Repository Registration

Repository registration is an authenticated but unscoped operation because no `repository_id` exists yet. Its machine command is:

```text
kos repository register --input <path|-> --idempotency-key <key> --json
```

It maps to `POST /api/v1/repositories` and does not accept `--repository`. The input contains `git_common_dir`, `trusted_remote`, `trusted_remote_url`, and full `base_ref`. `git_common_dir` is an absolute, already canonical path. The normalized URL is an absolute `https`, `ssh`, `git`, or `file` URI without a password, query, or fragment; an SSH username is allowed, and scp-like Git syntax is presented and submitted in equivalent `ssh://` form. The base ref is under `refs/heads/`.

Before calling this command, `kos-initialize` discovers and displays the canonical Git common directory, trusted remote name, normalized URL, and full base ref. It requires explicit human confirmation of those exact values. Automatic selection of `main` or `master` does not count as confirmation.

The API resolves the path without following a caller-selected identity assertion, verifies that it is a Git common directory, asks the repository adapter for the configured remote URL and base ref, normalizes those observed values independently, and compares them with the request. A missing or non-canonical common directory, missing remote or base ref, URL containing credentials, or mismatch with observed Git state returns `repository_registration_invalid` with safe details. The request path is never sufficient proof by itself.

The canonical Git common directory is globally unique among active registrations. Remote URL is not unique: separate clones may be registered separately. A first valid registration creates and returns a repository resource with an immutable UUID. A later call with another idempotency key and the same canonical common directory returns that existing resource when trusted remote name, normalized URL, and base ref all agree. If any trust setting differs, it returns `repository_registration_conflict` and changes nothing. Moving a checkout or changing trust settings requires a future explicit rebind or update contract; registration never performs that update implicitly.

`repository.register` always returns HTTP `200`, including creation, matching repeat, and completed idempotency replay, so callers do not infer durable identity from transport status. Its idempotency records use a global `repository.register` scope and the normal canonical request fingerprint with the repository component represented by the literal `global`. All other commands retain repository-scoped idempotency. A matching key and fingerprint replays the original resource; reuse with different input returns `idempotency_conflict`.

[ADR-0005](../decisions/0005-central-persistence-and-registration.md) records the architecture decision behind this contract.
