---
title: Clean OpenCode Runtime Installation Smoke Test
task: BOOT-039
created: 2026-09-14
---

# BOOT-039: Clean OpenCode Runtime Installation Smoke Test

## Goal

Manually verify that a clean Git repository receives a working OpenCode runtime installation whose installed skills remain discoverable without the source KOS bundle.

## User Outcome

A clean repository can install and discover the complete supported OpenCode 1.18.26 runtime bundle without retaining a dependency on the KOS source checkout.

## Context

BOOT-038 implemented and published the canonical initializer with automated installation and independent-copy coverage. A separate manual smoke test of the shipped command path remains required to complete the runtime-installation outcome.

## Requirements

- BOOT-039-REQ-001: Use a temporary clean non-bare Git repository, local bare remote, isolated KOS state and token, and isolated OpenCode/XDG configuration without changing development state.
- BOOT-039-REQ-002: Publish and activate a valid test `quick-fix` workflow in the isolated state so initialization readiness can be exercised.
- BOOT-039-REQ-003: Run `kos-initialize plan` from a nested repository directory and inspect repository identity, runtime version, readiness, nine managed-file actions, and the plan digest.
- BOOT-039-REQ-004: Apply the exact approved plan without force and verify the manifest, regular copied managed files, absence of managed symlinks, and preservation of unrelated `.opencode` content.
- BOOT-039-REQ-005: Remove the independent temporary source bundle, exclude the KOS checkout from the runtime command path, and verify discovery of all six installed skills through OpenCode 1.18.26 from a nested directory.
- BOOT-039-REQ-006: Repeat planning and verify that the manifest and all managed files are unchanged.
- BOOT-039-REQ-007: Record the exact smoke-test observations and required project checks.

## Scope

- Manual initialization and discovery verification in temporary isolated state.
- This task record and external bootstrap-plan status updates.

## Non-Goals

- Fixing a defect found by the smoke test.
- Changing installation or runtime contracts.
- Publishing the production `quick-fix` workflow.
- Exercising the complete orchestration lifecycle or live HTTPS/SSH authentication.

## Related Specifications And ADRs

- [KOS Project Initialization](../../docs/specs/initialization.md)
- [Runtime Integration](../../docs/specs/runtime-integration.md)
- [ADR-0008](../../docs/decisions/0008-opencode-runtime-adapter.md)
- [ADR-0009](../../docs/decisions/0009-runtime-bundle-installation.md)

## Task-Local Decisions

- BOOT-039-DEC-001: Use `/tmp/opencode` for disposable smoke-test files and a local bare remote.
- BOOT-039-DEC-002: Prove source independence by installing from a temporary copied source bundle, deleting that bundle, and running discovery with a runtime path that does not contain the KOS checkout.
- BOOT-039-DEC-003: A discovered product defect blocks this task and requires a separately approved correction rather than silently widening scope.

## Acceptance Criteria

- BOOT-039-AC-001: Planning and application complete successfully against isolated real KOS API state and OpenCode 1.18.26.
- BOOT-039-AC-002: The committed manifest is schema-valid, all nine managed files are regular non-symlink copies, and unrelated OpenCode content is preserved.
- BOOT-039-AC-003: OpenCode discovers all six installed KOS skills from a nested directory after the temporary source bundle is removed and the KOS checkout is absent from the runtime path.
- BOOT-039-AC-004: A repeated plan reports the expected manifest and all nine managed files as unchanged.
- BOOT-039-AC-005: `mise run check` and `git diff --check` pass.

## Implementation Plan

1. Record this approved baseline and mark BOOT-039 active externally.
2. Prepare isolated KOS state, API, local Git remote and repository, OpenCode environment, and copied source bundle.
3. Publish and activate the valid test workflow through the CLI.
4. Run and inspect initialization planning and application from a nested repository directory.
5. Verify the installed manifest, managed filesystem objects, and unrelated-file preservation.
6. Remove the source bundle and verify nested OpenCode skill discovery with an isolated runtime path.
7. Repeat planning, record results, and run the complete project quality gate and whitespace validation.
8. Update the external plan, commit only task files, and push normally to `main`.

## Verification

- Manual `kos-initialize plan` and `kos-initialize apply` against an isolated local API.
- Manifest schema validation and filesystem inventory checks.
- Real `opencode debug skill` discovery from a nested directory after source removal.
- Repeated initialization plan drift check.
- `mise run check`.
- `git diff --check`.

Completed smoke verification on 2026-09-14:

- Prepared an isolated SQLite state and loopback Rails API on port 3139, imported, published, and activated the valid `quick-fix@1.0.0` fixture exclusively through the version 1 CLI.
- Created a clean repository at `/tmp/opencode/boot-039-smoke/project`, pushed `main` to a local bare remote, and retained an unrelated `.opencode/user-owned.txt` file. The first path-style remote observation failed closed with `repository_invalid`; configuring the same remote as canonical `file:///tmp/opencode/boot-039-smoke/remote.git` allowed planning.
- Ran `kos-initialize plan --input /tmp/opencode/boot-039-smoke/initialize.json --json` from `nested/deeper` through an independent source copy. It discovered the canonical worktree and common directory, OpenCode 1.18.26, active workflow `094f119b-1573-4a06-8149-edb715b59f1d`, nine `create` actions, source digest `sha256:4ae39f492f80da569433652688d6ab4fa76f0f318b5ba732933499d1930b6f3b`, and plan digest `sha256:6e89a7cd00f6071bd9fa5cbf9e69b099377f65b7280b5e733b59249029026ad1`.
- Ran `kos-initialize apply` with that exact approved digest and without force. It registered repository `c6c5bf13-eb9d-4aee-a1b1-d3c8a7e35419` and published the expected nine managed files and manifest.
- Validated the committed manifest against `installer.json#/$defs/manifest`; all nine managed files were regular non-symlink files with matching SHA-256 digests, and the unrelated OpenCode file retained its exact bytes.
- Removed `/tmp/opencode/boot-039-smoke/source`, then ran the exact OpenCode 1.18.26 executable with an empty inherited environment, isolated HOME/XDG paths, and a PATH containing only the pinned OpenCode directory and system directories. `opencode debug skill` from `nested/deeper` discovered `kos-cli`, `kos-initialize`, `kos-orchestrate`, `kos-repository`, `kos-retrospective`, and `kos-workflow-step`, all from the installed repository paths.
- Repeated planning from the canonical source distribution. It retained the same source digest, observed the expected manifest for the same repository ID, and reported all nine managed files as `unchanged` with no drift.
- Final `mise run check` passed with 678 examples and no failures, 179 RuboCop-inspected files with no offenses, no Brakeman warnings, no dependency vulnerabilities, and successful Zeitwerk eager loading.
- `git diff --check` passed.

## Implementation Result

- The manual clean-installation smoke test passed without finding a product defect.
- The installed OpenCode runtime is discoverable independently of the temporary source bundle and does not contain managed symlinks back to that source.
- The initializer preserved unrelated OpenCode content and produced a stable clean repeated plan.

## Risks

- The smoke test verifies Linux and OpenCode 1.18.26 on this machine only.
- A local bare remote does not exercise live HTTPS or SSH authentication.
- Source-checkout independence is established through removed copied source bytes and an isolated command path rather than renaming the active development checkout.
