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

Initialization identifies repository identity, trusted remote name and normalized URL, full base ref, and canonical Git common directory, then registers them through the API after human confirmation. Automatic detection of `main` or `master` does not remove that confirmation requirement. The central state directory belongs to the Rails API, not the target repository.

## Safe Application

Before applying changes, initialization produces a machine-readable plan classifying create, update, and conflict operations. Overwriting any existing user file requires both `--force` and `--approved-plan <digest>`. `--force` does not delete or modify bundles pinned by unfinished tasks.

Skill installation records a manifest containing KOS and CLI protocol versions, runtime target, supported runtime-version range, and each installed skill's digest. Files are copied through staging and atomic rename. Without `--force`, detected drift fails with a description of differences.

Runtime target paths and required adapter capabilities are defined in [Runtime Integration](runtime-integration.md). Project configuration assets and pinning are defined in [Project Configuration](project-configuration.md). The operational MVP initializes one repository and one supported runtime target. BOOT-009 owns central state layout, migration policy, and repository-registration UX; detailed installation plan schemas and runtime adapter mechanics belong to later runtime-integration work.
