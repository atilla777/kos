---
title: Central Workflow Catalog
status: accepted
date: 2026-09-09
supersedes:
  - 0003-pinned-project-workflows
  - 0005-central-persistence-and-registration
---

# ADR-0007: Central Workflow Catalog

## Context

KOS is intended for one local installation serving a small number of repositories. Task state already belongs to the central Rails application, but the previous design made each target repository own `.kos` workflow files and required Rails to copy them into a separate filesystem snapshot store. That split adds initialization, path validation, snapshot materialization, garbage collection, and backup boundaries before any workflow can run.

The same task types and workflows will normally be shared by all registered repositories. Workflow behavior still needs to evolve without an application release, and an active task must keep executing the exact workflow version selected when the task was created.

## Decision

Rails owns a central workflow catalog in the same SQLite database as task state. The catalog stores shared task types, mutable workflow drafts, immutable published workflow versions, executable states, transitions, Markdown instructions, optional artifact templates, allowed typed repository effects, and artifact contracts.

A publication operation validates and creates a complete workflow version atomically. Published versions cannot be updated or deleted. Activating a published version changes the task type's current version only for tasks created afterward. A task references one published version by immutable identifier and does not copy the graph or store a bundle digest.

Workflow content is not sourced from target-repository `.kos` files, and KOS has no separate workflow snapshot filesystem. Artifact payloads such as task documents remain in the target Git repository; KOS stores the immutable metadata and evidence required to validate workflow transitions.

Every subagent workflow status is executed by the generic `kos-workflow-step` skill using the instruction stored in its pinned version. Mutating Git operations remain typed effects performed only by `kos-repository`; separate development, review, and publication skills are not part of the runtime model.

The first version uses one global current workflow version per task type. Repository-specific workflow assignments may be added later without changing existing task references.

## Consequences

- One SQLite-consistent backup contains both workflow definitions and workflow state.
- Task creation no longer reads a Git base ref or coordinates database state with snapshot materialization.
- Database constraints and triggers must protect published-version immutability and task/version/state consistency.
- Global workflow administration needs authenticated, versioned, idempotent CLI/API commands distinct from repository-scoped task execution.
- Export remains necessary for readable review, comparison, backup interchange, and transfer between KOS installations.
- Changing an instruction or template requires publishing a new workflow version; activating it never mutates existing tasks.
- Workflow content is unavailable if the central state is lost, so verified database backup and recovery remain mandatory.

## Rejected Alternatives

### Project-owned `.kos` workflows with central snapshots

This preserves Git-native workflow review but duplicates shared configuration across repositories and creates a second durable storage and reconciliation boundary for a small local installation.

### Mutable active workflow records

Updating a workflow in place could change instructions, allowed effects, or transition rules for an active task without an explicit migration.

### One copied workflow graph per task

Copies preserve behavior but duplicate data and make catalog identity, export, and version management harder than an immutable foreign-key reference.

### Specialized skill for every workflow activity

Development, review, and publication policy can be expressed by versioned step instructions. Separate prompt skills duplicate workflow content and complicate installation and compatibility.
