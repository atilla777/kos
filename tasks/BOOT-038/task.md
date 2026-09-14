---
title: Canonical KOS Initialization And OpenCode Runtime Installation
task: BOOT-038
created: 2026-09-14
---

# BOOT-038: Canonical KOS Initialization And OpenCode Runtime Installation

## Goal

Implement canonical `kos-initialize` behavior that registers one confirmed Git repository and safely installs the complete supported OpenCode runtime bundle without making the installed runtime depend on the KOS source checkout.

## User Outcome

A user can inspect and approve an exact initialization plan, register a repository through the KOS CLI, and install a complete OpenCode 1.18.26 runtime bundle. Repeated application is deterministic, drift and unsafe filesystem objects fail closed, and unrelated OpenCode configuration remains untouched.

## Context

The version 1 repository-registration machine contract, central persistence schema, canonical runtime skills, and executable OpenCode adapter contract already exist. The registration API and CLI command, canonical initialization skill, production OpenCode support files, installation plan and manifest, staging, and drift detection are not implemented. The test-only OpenCode session guard and agent profiles are not production installation sources.

## Requirements

- BOOT-038-REQ-001: Add a canonical `kos-initialize` skill that obtains the user's repository prefix and explicit base ref, displays the exact canonical common directory, normalized trusted remote URL, full base ref, runtime target, and planned files, and requires explicit approval before application.
- BOOT-038-REQ-002: Provide deterministic non-interactive `kos-initialize plan` and `kos-initialize apply` operations with closed versioned JSON input and output contracts.
- BOOT-038-REQ-003: Implement authenticated, globally idempotent `repository.register` through the existing Ruby CLI and `POST /api/v1/repositories`, always returning HTTP 200 for creation, a matching repeat, and replay.
- BOOT-038-REQ-004: Independently inspect and validate the canonical Git common directory, configured trusted remote, normalized credential-free URL, and full local base ref before registration. Preserve immutable matching-repeat and conflict semantics.
- BOOT-038-REQ-005: Normalize scp-like remote URLs consistently at registration and repository-operation trust checks so persisted and observed forms remain equivalent.
- BOOT-038-REQ-006: Install the six canonical skills, a production child-session guard plugin, and restrictive `kos-orchestrate` and `kos-workflow-step` OpenCode agent profiles as one managed bundle.
- BOOT-038-REQ-007: Support only OpenCode 1.18.26 under `.opencode`; reject bare repositories, other runtime targets, and other OpenCode versions.
- BOOT-038-REQ-008: Introduce KOS version `0.1.0`; bind each plan and manifest to that version, CLI protocol version 1, exact OpenCode version, complete source-bundle digest, and every managed file digest.
- BOOT-038-REQ-009: Classify each managed path as `create`, `update`, `unchanged`, or `conflict`. Existing unmanaged files remain conflicts even when byte-identical and are never silently adopted.
- BOOT-038-REQ-010: Rebuild and compare the complete approved plan before any registration or filesystem mutation. Every replacement requires both `--force` and an exact `--approved-plan` digest.
- BOOT-038-REQ-011: Reject path traversal, symlinks, non-regular managed objects, unsafe staging ancestry, malformed or unsupported manifests, and changed destination observations even with force.
- BOOT-038-REQ-012: Stage and verify the complete bundle on the target filesystem, publish each file by atomic rename, and publish the manifest last as the installation commit marker. Attempt best-effort rollback after an in-process publication error; treat crash residue as drift requiring a newly approved recovery plan.
- BOOT-038-REQ-013: Preserve all unrelated `.opencode` content and never remove files not named by the approved managed-file inventory.
- BOOT-038-REQ-014: Before successful application, verify installed `kos` and `kos-repository` executables, an active readable published `quick-fix` workflow, OpenCode 1.18.26, and every required executable adapter capability against the staged bundle.
- BOOT-038-REQ-015: Discover the current non-bare worktree from nested directories, prove that it belongs to the canonical common directory, and install ordinary copied files rather than symlinks.
- BOOT-038-REQ-016: Keep the installed runtime discoverable after the source bundle or KOS checkout is unavailable. Do not claim the still-unimplemented OpenCode retrospective lifecycle transport.
- BOOT-038-REQ-017: Add deterministic contract, request, service, CLI, installer, drift, security, recovery, and pinned-runtime coverage for the behavior above.

## Scope

- Repository registration inspection, application operation, REST endpoint, serializer, and CLI binding.
- Shared remote URL normalization used by registration and repository operations.
- Canonical initialization skill and deterministic initialization executable.
- Closed installation plan and manifest schemas.
- Production OpenCode skills, session guard, and restrictive agent profiles.
- Installation locking, staging, atomic per-file publication, rollback, manifest, and drift detection.
- Required capability and workflow readiness checks.
- Applicable specifications, architecture decision, user documentation, and external bootstrap plan updates.

## Non-Goals

- Materializing `AGENTS.md`, `README.md`, or `docs/` templates.
- Supporting Claude or an OpenCode version other than 1.18.26.
- Packaging the Rails application or installing `kos` and `kos-repository` system-wide.
- Implementing retrospective lifecycle hooks, private-dialogue extraction, timeout enforcement, or second-result delivery.
- Publishing the quick-fix workflow or filling remaining workflow, publication, and runtime-orchestration gaps.
- Changing existing workflow semantics.

## Related Specifications And ADRs

- [KOS Project Initialization](../../docs/specs/initialization.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [Central Persistence](../../docs/specs/central-persistence.md)
- [CLI Protocol Version 1](../../docs/specs/cli-protocol.md)
- [Repository Isolation](../../docs/specs/repository-isolation.md)
- [ADR-0005](../../docs/decisions/0005-central-persistence-and-registration.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)

## Task-Local Decisions

- BOOT-038-DEC-001: The complete OpenCode production bundle contains all six canonical skills, the child-session guard, and restrictive orchestrator and workflow-step agent profiles.
- BOOT-038-DEC-002: Installation manifests identify KOS version `0.1.0` and additionally bind the exact source bundle digest.
- BOOT-038-DEC-003: Git remote URLs are normalized at both registration and repository-operation boundaries; scp-like syntax remains supported.
- BOOT-038-DEC-004: A user supplies the full base ref. Initialization may display an unambiguous suggestion but never treats it as confirmation.
- BOOT-038-DEC-005: A pre-existing path without a valid owning manifest is an unmanaged conflict even when its bytes equal the proposed content.
- BOOT-038-DEC-006: The manifest is the bundle commit marker. Atomicity is per file; interrupted multi-file publication is recovered only through a newly generated and approved plan.
- BOOT-038-DEC-007: Workflow readiness means that `quick-fix` has a non-null active published workflow version that can be read successfully; this task does not require a particular semantic version.

## Acceptance Criteria

- BOOT-038-AC-001: `kos repository register` and its API endpoint satisfy the existing closed request, response, stable error, status, idempotency, concurrency, and immutable-repeat contracts.
- BOOT-038-AC-002: Registration independently verifies canonical Git identity and trust settings and accepts equivalent normalized scp-like and SSH URI remote forms.
- BOOT-038-AC-003: Initialization planning returns one schema-valid document containing exact repository, runtime, source, readiness, managed-file observations, and canonical plan digest.
- BOOT-038-AC-004: Application rejects a missing or stale plan digest before mutations and requires force for every changed existing destination.
- BOOT-038-AC-005: The installed bundle contains exactly the approved KOS-managed six skills, session guard, and two agent profiles as regular copied files plus the manifest.
- BOOT-038-AC-006: The closed manifest records KOS 0.1.0, CLI protocol 1, OpenCode 1.18.26, repository identity, source digest, and every managed path and digest.
- BOOT-038-AC-007: Drift, missing managed files, unmanaged collisions, symlinks, wrong object types, traversal, unsafe ancestry, and malformed or unsupported manifests fail closed without changing unrelated files.
- BOOT-038-AC-008: Publication uses same-filesystem staging and atomic rename with the manifest last; injected failure rolls back best-effort and crash residue requires a new approved recovery plan.
- BOOT-038-AC-009: Required executables, active published quick-fix workflow, runtime version, and complete staged OpenCode capability report all pass before initialization succeeds.
- BOOT-038-AC-010: A nested target directory discovers the installed runtime bundle after the source bundle is unavailable and no runtime path is a symlink into the KOS checkout.
- BOOT-038-AC-011: Existing schemas, persistence, workflow behavior, canonical skills, repository operations, and retrospective capability claims remain compatible except for the approved registration and URL-normalization additions.
- BOOT-038-AC-012: Focused suites, complete `mise run check`, and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-038 active externally.
2. Implement shared Git discovery and URL normalization, repository registration policy, API endpoint, serializer, and CLI binding with focused tests.
3. Add the KOS version, closed installation schemas, canonical initialization skill, production session guard, and restrictive OpenCode agent profiles.
4. Implement deterministic repository discovery, source inventory, plan generation, manifest validation, locking, staging, atomic publication, rollback, and drift handling.
5. Add executable readiness and staged OpenCode capability verification without weakening the existing adapter contract.
6. Add end-to-end initialization, security, failure-injection, independent-copy discovery, and affected regression coverage.
7. Update applicable specifications, add an installation architecture decision, and update user documentation without duplicating roadmap state.
8. Run focused tests, the full project quality gate, and whitespace validation; review the complete diff.
9. Record verification and implementation results, update the external plan, commit only task files, and push normally to `main`.

## Verification

- Run focused registration, CLI, installation, runtime, and repository adapter specs while iterating.
- Run the affected schema and canonical skill contracts.
- Run `mise run check`.
- Run `git diff --check`.

Completed verification on 2026-09-14:

- Registration, CLI, idempotency, process-concurrency, Git URL, and repository adapter focused suites passed with 146 examples and no failures before the final concurrency barrier assertion; the final process-concurrency suite passed separately with 4 examples and no failures.
- Initialization, manifest, descriptor-safe filesystem, subprocess timeout, capability verifier, canonical skill, and real OpenCode 1.18.26 focused suites passed with 35 examples and no failures.
- Final `mise run check` passed with 678 examples and no failures, 179 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.
- Two independent reviews found and verified fixes for scp-like transport semantics, transient idempotency, destination and staging ancestry races, manifest races and identity, directory durability, rollback reporting, subprocess bounds, and production profile validation. No high- or medium-severity registration findings remained.

## Implementation Result

- Implemented authenticated global `repository.register` through the REST API and Ruby CLI with independent Git inspection, immutable matching-repeat behavior, stable conflicts, global idempotency, process-concurrency coverage, and non-persisted transient inspection failures.
- Added shared credential-free Git URL normalization. Persisted normalized trust identities compare equivalent scp-like and SSH forms, while fetch and publication preserve the exact configured raw transport URL and therefore its relative-path semantics.
- Added KOS version 0.1.0, the canonical `kos-initialize` skill, closed installation version 1 schemas, and deterministic non-interactive `plan` and `apply` operations.
- Added the production OpenCode bundle containing all six canonical skills, the session guard, and restrictive orchestrator and workflow-step agent profiles.
- Added exact plan approval, force-gated update and drift recovery, ownership manifests, source and capability digests, stale-plan detection, unrelated-file preservation, and fail-closed handling for unmanaged, malformed, symlinked, or wrong-type destinations.
- Implemented Linux descriptor-relative, no-follow destination and staging traversal; same-filesystem staging; digest checks before and after executable verification; per-file atomic rename; parent-directory fsync; manifest-last publication; mode-preserving rollback; and explicit incomplete-rollback failure.
- Promoted the deterministic loopback OpenCode capability verifier into production code. It verifies exact version, complete installed discovery, effective agent restrictions, non-interactive JSON execution, foreground child routing, worktree cwd, guard rejection, and typed-effect round trip with bounded process-group cleanup.
- Added independent-copy coverage proving nested OpenCode discovery after the temporary source bundle is removed.
- Documented initialization behavior and ADR-0009 without claiming the unavailable retrospective lifecycle transport.

## Risks

- Repository registration and filesystem installation cannot share one transaction. A safely repeatable apply must complete or report partial progress without changing the immutable registration.
- Atomic rename protects each file, while the manifest marks completion of the whole bundle. Process death may leave files that require an explicit newly approved recovery plan.
- OpenCode skill instructions and permission profiles reduce authority but are not by themselves a complete security boundary.
- OpenCode 1.18.26 cannot deny every indirect Git or KOS invocation while allowing arbitrary project shell tools; workflow-step isolation therefore still depends on the canonical procedural contract in addition to its direct command deny patterns.
- This task proves copied-runtime independence, not a final distributable packaging format for the KOS application.
- The retrospective skill is installed, but graceful-end invocation and second-result transport remain unavailable.
- Descriptor-relative installation intentionally requires Linux and `/proc/self/fd`; unsupported hosts fail closed.
- A same-user hostile process can attempt to escape process groups or mutate files after installation; the bounded verifier and next initialization plan detect ordinary descendant hangs and post-installation drift but are not an operating-system sandbox.
