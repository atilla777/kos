---
title: KOS Project Configuration
status: active
---

# KOS Project Configuration

## Ownership And Layout

Workflow schemas, task types, step instructions, and templates belong to the target project and are versioned in its Git repository under `.kos/`. Rails and the CLI load and validate the configuration; orchestration and step skills execute its process instructions.

A project may use this shape:

```text
.kos/
  task-types/
    quick-fix.yaml
    feature.yaml
    initiative.yaml
  workflows/
    quick-fix/<version>/
      workflow.yaml
      steps/
    feature/<version>/
      workflow.yaml
      steps/
    initiative/<version>/
      workflow.yaml
      steps/
  templates/
    requirements/<version>/
      template.yaml
      template.md
```

`task-types/<type>.yaml` points to the current version of that type's sole workflow. A new task resolves this pointer only from the pinned authoritative base ref. `workflow.yaml` declares statuses, transitions, execution modes, instructions, and artifact contracts. Each instruction states the step goal, input context, allowed capability skills, required artifacts, checks, and completion criterion.

The operational MVP ships a complete `quick-fix` workflow. The `feature` and `initiative` definitions and their branches described in [Workflow Execution](workflow-execution.md) are deferred increments.

## Versioning And Snapshot Bundles

Workflow schema and template versions are part of their contract:

- changed behavior is published as a new version, such as `1.1.0` or `2.0.0`;
- an already published version is immutable;
- a task records task type, workflow identity, version, and SHA-256 digest;
- a complete workflow bundle contains `workflow.yaml`, every status instruction, and every referenced template;
- task creation stores a content-addressed snapshot outside the task worktree;
- the snapshot manifest contains sorted repository-relative paths and each file's SHA-256 content digest;
- absolute paths, `..`, symlinks, and references outside the bundle are rejected;
- a digest mismatch blocks workflow transitions as inconsistent, while the snapshot remains available to continue the original task; and
- new tasks use the task type's current version while started tasks continue their pinned version.

The Rails application reads execution members only from the immutable snapshot, never `.kos/` from the current task worktree. It verifies the bundle and selected members and returns the complete instruction and referenced materials through the CLI's attempt-bound step-context operation. Orchestrators, subagents, and runtime skills do not receive snapshot storage paths or read snapshot files directly. Project instructions and capability skills are trusted project code, but the orchestrator invokes only capabilities allowed by the pinned bundle. Changes to `.kos/` do not affect an already started task.

[ADR-0003](../decisions/0003-pinned-project-workflows.md) records the decision to use project-controlled, immutable snapshot bundles. BOOT-008 will define the detailed YAML schema and canonical bundle-digest algorithm without changing these guarantees.

`kos-initialize` materializes the initial `.kos/` configuration and templates from versioned assets as specified by [Initialization](initialization.md).
