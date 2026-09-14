---
title: Runtime Bundle Installation
status: accepted
date: 2026-09-14
---

# ADR-0009: Runtime Bundle Installation

## Context

KOS runtime files must be installed into a target repository without making that installation depend on an editable KOS checkout. Installation changes several user-visible paths, must preserve unrelated runtime configuration, and cannot rely on a filesystem-wide transaction. OpenCode also needs production agent profiles and a child-session guard in addition to canonical skills.

## Decision

The installed OpenCode bundle contains ordinary copies of the six canonical skills, the KOS session-guard plugin, and restrictive orchestrator and workflow-step agent profiles. The source distribution identifies itself as KOS 0.1.0 and binds each plan and installation to the complete source-bundle digest.

`kos-initialize` separates deterministic planning from application. A plan records repository trust values, runtime and workflow readiness, source identity, destination observations, and a canonical digest. Application rebuilds that plan under a repository installation lock and requires its exact approved digest. Any update, drift recovery, or unmanaged collision also requires explicit force authorization. Symlinks, wrong object types, unsafe ancestry, malformed manifests, and changed observations always fail closed.

Files are prepared and verified in staging on the target filesystem, then published by per-file atomic rename. The closed manifest is published last and acts as the bundle commit marker. An in-process error attempts rollback; interruption without a committed manifest is handled as drift through a newly generated and approved plan rather than implicit continuation. The initializer runs the complete executable OpenCode adapter contract against the staged bundle before publication.

## Consequences

- Installed runtime discovery no longer reads canonical files from the KOS checkout.
- Unrelated OpenCode files remain outside KOS ownership.
- Safe upgrades require a new approved plan and force authorization when installed bytes change.
- Atomicity is per file rather than across the whole bundle; the manifest distinguishes a completed installation from crash residue.
- The first installation target remains exactly OpenCode 1.18.26. Supporting another version requires passing the complete adapter contract and changing the closed installation contract.
- KOS application packaging remains separate; the initializer consumes bundle files from its installed distribution and requires `kos` and `kos-repository` to already be on `PATH`.

## Rejected Alternatives

### Symlink runtime files to the KOS checkout

This would make runtime behavior depend on checkout location and mutable source state.

### Adopt byte-identical unmanaged files

Matching bytes do not establish ownership. Silent adoption could later overwrite a user-managed file.

### Publish the manifest before bundle files

A crash could present an incomplete bundle as a committed installation.

### Trust only the OpenCode version string

The required discovery, session routing, working-directory, and typed-effect behavior must be exercised rather than inferred from a version label.
