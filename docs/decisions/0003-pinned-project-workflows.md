---
title: Pinned Project Workflows
status: superseded
date: 2026-09-08
superseded_by: 0007-central-workflow-catalog
---

# ADR-0003: Pinned Project Workflows

This decision is superseded by [ADR-0007](0007-central-workflow-catalog.md). It is retained as historical context for the completed bootstrap tasks that established the former project-owned snapshot contract.

## Context

Projects need to evolve task types, workflow graphs, step instructions, and templates without changing KOS application code. A task may remain active while project configuration changes, so reading mutable `.kos/` files during execution would make the task irreproducible and could change its allowed capabilities mid-workflow.

## Decision

Workflow policy is version-controlled project configuration under `.kos/`, not application or CLI policy. Task creation resolves the task type from the authoritative base ref and stores workflow identity, version, and the digest of a complete content-addressed snapshot bundle outside the task worktree.

Published versions and snapshots are immutable. Every execution reads only the pinned snapshot. The bundle contains the workflow, all status instructions, and referenced templates; its capability allowlist bounds trusted project instructions. New tasks may use a newer version, while started tasks remain pinned.

The observable contract is defined in [Project Configuration](../specs/project-configuration.md).

## Consequences

- Workflow behavior can evolve independently of KOS releases.
- Active tasks remain reproducible and unaffected by task-worktree edits to `.kos/`.
- Bundle creation, path safety, digest verification, and snapshot retention are required.
- BOOT-008 must define a canonical bundle schema and digest algorithm consistent with this decision.

## Rejected Alternatives

### Embed workflow policy in Rails or the CLI

This couples process evolution to application releases and prevents target projects from controlling their workflow.

### Read current `.kos/` files for every step

This allows an in-progress task's contract and executable capabilities to change without an explicit migration.

### Pin only a version string

A version label alone does not prove the exact content executed or preserve it after repository changes.
