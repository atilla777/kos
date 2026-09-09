---
title: Central State And Repository Registration Contract
task: BOOT-009
created: 2026-09-09
---

# BOOT-009: Central State And Repository Registration Contract

## Goal

Define the central state layout, migration policy, repository-registration experience, and persistence boundary so persistence implementation can proceed without implicit architecture decisions.

## User Outcome

A production KOS installation stores durable state independently of its source checkout, upgrades that state explicitly, and registers a Git repository through a confirmed, idempotent operation with stable trust settings.

## Context

KOS already requires one central Rails-owned SQLite database, immutable workflow snapshots outside task worktrees, repository-scoped records, and registration of a canonical Git common directory, trusted remote, and base ref. It does not yet define the production state root, snapshot placement protocol, migration operation, repeated-registration behavior, or exact ownership boundary between Active Record and filesystem adapters.

## Requirements

- BOOT-009-REQ-001: Default production state to `$XDG_STATE_HOME/kos`, falling back to `~/.local/state/kos`, with explicit database and snapshot-root overrides.
- BOOT-009-REQ-002: Keep the SQLite database, content-addressed workflow snapshots, and same-filesystem snapshot staging under central state while excluding credentials, task worktrees, and repository checkouts.
- BOOT-009-REQ-003: Apply production schema migrations only through an explicit idempotent operation while the service is stopped, and refuse normal service operation when migrations are pending.
- BOOT-009-REQ-004: Define SQLite-consistent backup and restore, forward migration, failed-migration, and unsupported-downgrade behavior without automatic destructive rollback.
- BOOT-009-REQ-005: Add an unscoped, authenticated, idempotent `repository.register` CLI/API contract that returns the immutable repository identifier and verified trust settings.
- BOOT-009-REQ-006: Require initialization to present the canonical Git common directory, trusted remote name and normalized URL, and full base ref for human confirmation before registration.
- BOOT-009-REQ-007: Repeating registration for the same canonical Git common directory returns the existing repository when trust settings agree and returns a conflict when they differ.
- BOOT-009-REQ-008: Treat the canonical Git common directory as unique while allowing multiple registrations with the same remote URL; do not trust a caller-supplied path as proof of repository identity.
- BOOT-009-REQ-009: Restrict SQLite access to Rails persistence code and workflow snapshot paths to a dedicated Rails filesystem adapter; CLI and runtime clients receive no storage paths.
- BOOT-009-REQ-010: Materialize and verify a content-addressed snapshot through same-filesystem staging and atomic rename before a short database transaction references it.

## Scope

- Add a focused central persistence specification and architecture decision.
- Update initialization, repository isolation, CLI protocol, architecture documentation, and their indexes where required.
- Extend the unreleased CLI v1 schemas with repository registration request, result, resource, errors, and transport binding.
- Add representative valid and invalid fixtures and contract assertions.
- Update the external bootstrap plan, commit the verified result, and publish it normally to the default branch.

## Non-Goals

- Implementing migrations, Active Record models, controllers, CLI command handling, or snapshot storage.
- Updating, rebinding, unregistering, or deleting a repository registration.
- Adding replaceable persistence or snapshot backends.
- Adding scheduled backups, encryption, remote state, or runtime installation-plan schemas.
- Storing task worktrees, repository checkouts, bearer tokens, or other credentials in central state.

## Related Specifications And ADRs

- [Product Boundary](../../docs/specs/product-boundary.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Project Configuration](../../docs/specs/project-configuration.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Initialization](../../docs/specs/initialization.md)
- [ADR-0001: Central REST API and Multi-Repository State](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0003: Pinned Project Workflows](../../docs/decisions/0003-pinned-project-workflows.md)

## Task-Local Decisions

- BOOT-009-DEC-001: Use the XDG state convention with a home-directory fallback instead of coupling production data to the KOS checkout or requiring every path explicitly.
- BOOT-009-DEC-002: Require an explicit production migration operation instead of applying DDL during normal service startup.
- BOOT-009-DEC-003: Make matching repeated registration return the existing resource; do not use registration as an implicit trust-settings update.
- BOOT-009-DEC-004: A moved checkout requires a future explicit rebind contract; BOOT-009 does not infer that two different common directories are one repository from remote URL alone.

## Acceptance Criteria

- BOOT-009-AC-001: The production state paths, ownership, exclusions, permissions, and atomic workflow-snapshot placement are unambiguous.
- BOOT-009-AC-002: Migration startup, upgrade, backup, failure, restore, and downgrade semantics are defined without a pluggable backend.
- BOOT-009-AC-003: Repository registration request, response, idempotent replay, identity verification, and trust-setting conflict behavior are normative.
- BOOT-009-AC-004: CLI v1 schemas validate against JSON Schema draft 2020-12, resolve locally, and cover valid and invalid repository registration documents.
- BOOT-009-AC-005: All required project checks pass and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-009 active externally.
2. Add the central persistence specification and architecture decision.
3. Align related specifications, rules, and documentation indexes.
4. Extend draft CLI v1 schemas, catalog, fixtures, and contract tests for repository registration.
5. Run focused and full test, lint, security, autoloading, and diff checks.
6. Update the external plan, commit the task files, and push normally to the default branch.

## Verification

- Run `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb` while iterating.
- Run `bundle exec rspec`.
- Run `bundle exec rubocop`.
- Run `bin/rails zeitwerk:check`.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Verification Results

- `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb`: 143 examples, 0 failures.
- `bundle exec rspec spec/contracts/project_configuration_v1_contract_spec.rb`: 39 examples, 0 failures.
- `bundle exec rspec`: 183 examples, 0 failures.
- `bundle exec rubocop`: 22 files inspected, no offenses.
- `bin/rails zeitwerk:check`: passed.
- `mise run check`: passed, including Brakeman with no warnings and bundler-audit with no vulnerabilities.
- `git diff --check`: passed.

## Risks

- Workflow snapshot files are not transactional with SQLite; immutable content addressing, same-filesystem atomic rename, and ordering before the referencing transaction must prevent partial snapshots from becoming reachable.
- A relocated Git common directory cannot be safely adopted without a future explicit rebind and identity-verification contract.
- The unscoped repository-registration endpoint needs authentication and a deliberately narrow authorization path because repository scope does not exist yet.
