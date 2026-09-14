---
title: KOS Project Initialization
status: active
---

# KOS Project Initialization

## Initialization Contract

`kos-initialize`:

1. Identifies the target Git repository.
2. Optionally materializes initial `AGENTS.md`, `README.md`, and `docs/` content from versioned templates.
3. Copies selected KOS skills and required runtime-adapter support files into native runtime paths.
4. Does not overwrite an existing user file without explicit `--force` authorization.
5. Verifies CLI availability, required published workflows in KOS, and the complete adapter capability contract for the selected runtime.

Initialization asks the user for a repository task prefix, identifies the canonical Git common directory, trusted remote name and normalized URL, and full base ref, displays those exact values, and requires human confirmation before invoking the idempotent `repository.register` CLI command. The prefix must already satisfy the uppercase format; initialization does not silently normalize it. Automatic detection of `main` or `master` does not remove the confirmation requirement. The server validates prefix availability and independently verifies the submitted Git values as defined by [Central Persistence](central-persistence.md). The central state directory belongs to the Rails API, not the target repository.

## Safe Application

Before applying project-file or runtime-copy changes, initialization produces a machine-readable plan classifying create, update, and conflict operations. Overwriting any existing user file requires both `--force` and `--approved-plan <digest>`. Initialization never edits published workflow versions or changes the version pinned by an existing task.

Skill installation records `.opencode/kos-runtime-manifest.json` containing KOS and CLI protocol versions, the exact runtime target and version, repository identity and trust values, the executable capability-report digest, the complete source-bundle digest, and every managed file's source and digest. Files are copied through same-filesystem staging and per-file atomic rename, with the manifest published last as the bundle commit marker. Without `--force`, an update, unmanaged collision, missing managed file, or other detected drift fails with a description of differences. Symlinks, wrong object types, unsafe ancestry, malformed manifests, and changed plan observations fail even with force.

The operational interface is non-interactive `kos-initialize plan|apply` with closed version 1 JSON documents. Planning classifies each managed path as `create`, `update`, `unchanged`, or `conflict` and returns a canonical `plan_digest`. Application rebuilds the plan under the repository installation lock, requires `--approved-plan` to match exactly, and requires `--force` for every `update` or `conflict`. An unmanaged existing file is a conflict even when its bytes equal the proposed source. Application attempts rollback after an in-process publication failure; crash residue requires a newly generated and explicitly approved recovery plan.

Runtime target paths, supported versions, and required adapter capabilities are defined in [Runtime Integration](runtime-integration.md). OpenCode compatibility is reported with the closed runtime schema and requires every capability observation to pass against the staged production bundle. The complete bundle contains the six canonical skills, `kos-session-guard.js`, and restrictive `kos-orchestrate` and `kos-workflow-step` agent profiles. Shared workflow publication and pinning are defined in [Workflow Catalog](workflow-catalog.md). The operational MVP initializes one non-bare repository worktree and one supported runtime target. [ADR-0009](../decisions/0009-runtime-bundle-installation.md) records the installation and recovery mechanism.
