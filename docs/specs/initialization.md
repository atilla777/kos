---
title: KOS Project Initialization
status: active
---

# KOS Project Initialization

## Initialization Contract

`kos-initialize`:

1. Identifies the target Git repository.
2. Materializes initial `AGENTS.md`, `README.md`, `docs/`, and `.kos/` content from versioned templates.
3. Copies selected KOS skills into native runtime paths.
4. Does not overwrite an existing user file without explicit `--force` authorization.
5. Verifies CLI availability, workflow configuration validity, and skill discovery by the selected runtime.

Initialization asks the user for a repository task prefix, identifies the canonical Git common directory, trusted remote name and normalized URL, and full base ref, displays those exact values, and requires human confirmation before invoking the idempotent `repository.register` CLI command. The prefix must already satisfy the uppercase format; initialization does not silently normalize it. Automatic detection of `main` or `master` does not remove the confirmation requirement. The server validates prefix availability and independently verifies the submitted Git values as defined by [Central Persistence](central-persistence.md). The central state directory belongs to the Rails API, not the target repository.

## Safe Application

Before applying changes, initialization produces a machine-readable plan classifying create, update, and conflict operations. Overwriting any existing user file requires both `--force` and `--approved-plan <digest>`. `--force` does not delete or modify bundles pinned by unfinished tasks.

Skill installation records a manifest containing KOS and CLI protocol versions, runtime target, supported runtime-version range, and each installed skill's digest. Files are copied through staging and atomic rename. Without `--force`, detected drift fails with a description of differences.

Runtime target paths and required adapter capabilities are defined in [Runtime Integration](runtime-integration.md). Project configuration assets and pinning are defined in [Project Configuration](project-configuration.md). The operational MVP initializes one repository and one supported runtime target. Detailed installation plan schemas and runtime adapter mechanics belong to later runtime-integration work.
