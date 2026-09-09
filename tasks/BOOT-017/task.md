---
title: Repository Task Prefix Contract
task: BOOT-017
created: 2026-09-09
---

# BOOT-017: Repository Task Prefix Contract

## Goal

Replace the fixed `TASK-000123` public-number format with a repository-specific prefix such as `KOS-000123` before persistence implementation begins.

## User Outcome

When registering a repository, a user selects a stable prefix that makes every task number, task artifact, branch, and Git reference recognizably belong to that project.

## Context

The current specifications and draft CLI v1 schemas hard-code `TASK-` in public numbers and branch names. KOS serves multiple repositories, so a fixed prefix does not identify the owning project without additional repository context. BOOT-010 will implement the base persistence schema and needs this identity contract settled first.

## Requirements

- BOOT-017-REQ-001: Require `task_prefix` when registering a repository and return it in the repository resource.
- BOOT-017-REQ-002: Accept prefixes of 2 through 10 ASCII characters that begin with `A-Z` and otherwise contain only `A-Z` or `0-9`; reject lowercase rather than normalizing it.
- BOOT-017-REQ-003: Keep a repository's prefix immutable and globally unique within one KOS installation.
- BOOT-017-REQ-004: Return `repository_registration_conflict` when the same repository is registered with another prefix or another repository requests an occupied prefix.
- BOOT-017-REQ-005: Represent a public task number as `<PREFIX>-<six decimal digits>`, with the numeric sequence unique and never reused within its repository.
- BOOT-017-REQ-006: Use the repository-specific public number consistently in CLI and API values, task paths, traceability IDs, branch names, Git trailers, and human or agent references.
- BOOT-017-REQ-007: Include the exact task prefix among the repository-registration values that initialization presents for explicit human confirmation.

## Scope

- Add an architecture decision for repository task prefixes.
- Update task, persistence, initialization, repository-isolation, publication, CLI, and collaboration contracts where they assume the fixed prefix.
- Update draft CLI v1 registration, public-number, and branch schemas.
- Update representative fixtures and contract assertions for valid and invalid prefixes and public numbers.
- Update the external bootstrap plan, commit the verified result, and publish it normally to the default branch.

## Non-Goals

- Implementing Active Record models, migrations, task-number allocation, repository registration, or CLI handling.
- Renaming a repository prefix after registration or retaining prefix history.
- Expanding public task numbers beyond six decimal digits.
- Starting BOOT-010 in this session.

## Related Specifications And ADRs

- [Task Model](../../docs/specs/task-model.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [Initialization](../../docs/specs/initialization.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [Publication](../../docs/specs/publication.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [ADR-0001: Central REST API and Multi-Repository State](../../docs/decisions/0001-central-rest-api.md)
- [ADR-0005: Central Persistence And Repository Registration](../../docs/decisions/0005-central-persistence-and-registration.md)

## Task-Local Decisions

- BOOT-017-DEC-001: Make prefixes globally unique so a public task number identifies one repository without additional context.
- BOOT-017-DEC-002: Use a short uppercase alphanumeric format and reject lowercase input instead of silently normalizing identifiers.
- BOOT-017-DEC-003: Keep prefixes immutable so existing task references, branches, artifacts, and Git trailers remain stable.
- BOOT-017-DEC-004: Change the unreleased draft CLI v1 contract in place rather than introducing a second protocol version.

## Acceptance Criteria

- BOOT-017-AC-001: The normative contract defines prefix format, ownership, global uniqueness, immutability, registration conflicts, and human confirmation.
- BOOT-017-AC-002: CLI v1 schemas accept repository-specific values such as `KOS-000123` and reject invalid prefixes and public-number shapes.
- BOOT-017-AC-003: Registration request and repository resource require `task_prefix`.
- BOOT-017-AC-004: Task paths, traceability IDs, Git branches, and task trailers use one consistent repository-specific public number.
- BOOT-017-AC-005: All required project checks pass and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved baseline and mark BOOT-017 active externally.
2. Add the architecture decision and align affected specifications and rules.
3. Update draft CLI v1 schemas, fixtures, and contract tests.
4. Run focused and full test, lint, security, autoloading, and diff checks.
5. Record verification, update the external plan, commit the task files, and push normally to the default branch.

## Verification

- Run `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb` while iterating.
- Run `bundle exec rspec`.
- Run `bundle exec rubocop`.
- Run `bin/rails zeitwerk:check`.
- Run `mise run check`.
- Run `git diff --check`.
- Allow configured commit and push hooks to run without bypassing them.

## Verification Results

- `bundle exec rspec spec/contracts/cli_v1_contract_spec.rb spec/contracts/task_model_contract_spec.rb`: 159 examples, 0 failures.
- `mise run check`: passed, including 199 RSpec examples, RuboCop with no offenses, Brakeman with no warnings, bundler-audit with no vulnerabilities, and Zeitwerk validation.
- `git diff --check`: passed.
- Independent final review: no findings; persistence and runtime enforcement remain intentionally deferred to their assigned implementation tasks.

## Risks

- BOOT-017-RISK-001: Global uniqueness may require a user to choose another prefix when the preferred project abbreviation is already registered.
- BOOT-017-RISK-002: Six decimal digits limit one repository to 999999 public task numbers; exhaustion must fail explicitly when allocation is implemented.
- BOOT-017-RISK-003: The public number crosses CLI, filesystem, and Git contracts, so stale fixed-prefix assumptions could create inconsistent references without comprehensive contract coverage.
