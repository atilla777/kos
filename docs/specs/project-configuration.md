---
title: KOS Project Configuration
status: active
---

# KOS Project Configuration

## Ownership And Layout

Workflow schemas, task types, step instructions, and materials belong to the target project and are versioned in its Git repository under `.kos/`. Rails and the CLI load and validate the configuration; orchestration and step skills execute its process instructions.

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
      materials/
    feature/<version>/
      workflow.yaml
      steps/
      materials/
    initiative/<version>/
      workflow.yaml
      steps/
      materials/
  materials/
    requirements/<version>/
      requirements.md
```

`task-types/<type>.yaml` points to the current version of that type's sole workflow. A new task resolves this pointer only from the pinned authoritative base ref. `workflow.yaml` declares statuses, transitions, execution modes, direct instructions and materials, capability allowlists, repository policy, and artifact contracts. Instruction and material files contain project-controlled execution content; there are no member descriptors or recursive member references in version 1.

The operational MVP ships a complete `quick-fix` workflow. The `feature` and `initiative` definitions and their branches described in [Workflow Execution](workflow-execution.md) are deferred increments.

## Versioning And Snapshot Bundles

Workflow schema and referenced-member versions are part of their contract:

- changed behavior is published as a new version, such as `1.1.0` or `2.0.0`;
- an already published version is immutable;
- a task records task type, workflow identity, version, and SHA-256 digest;
- a complete workflow bundle contains `workflow.yaml`, every status instruction, and every directly referenced material;
- task creation stores a content-addressed snapshot outside the task worktree;
- the snapshot manifest contains byte-sorted repository-relative paths and each file's `sha256:<lowercase-hex>` content digest;
- absolute paths, `..`, symlinks, and references outside the bundle are rejected;
- a digest mismatch blocks workflow transitions as inconsistent, while the snapshot remains available to continue the original task; and
- new tasks use the task type's current version while started tasks continue their pinned version.

The generated manifest has exactly `schema_version`, `workflow_id`, `workflow_version`, and `members`. Each member has exactly `path` and `digest`, where `digest` is `sha256:<64 lowercase hex>`; members are unique and sorted lexicographically by their UTF-8 path bytes. The complete closure consists of `workflow.yaml` and every instruction and material directly named by it. The task-type pointer selects the workflow but is not a bundle member. A member digest is SHA-256 over the exact file bytes without text, newline, encoding, or whitespace normalization. Hashing happens before and independently of UTF-8 decoding, so line-ending and trailing-newline changes produce different member and bundle digests.

The bundle digest is `sha256:` followed by SHA-256 over the UTF-8 bytes of the RFC 8785 JSON Canonicalization Scheme serialization of the complete manifest. The manifest has no `bundle_digest` field, so the digest input has no recursive omission rule. The task stores the resulting digest separately.

The Rails application reads execution members only from the immutable snapshot, never `.kos/` from the current task worktree. It verifies the bundle and selected members and returns the complete instruction and referenced materials through the CLI's attempt-bound step-context operation. Orchestrators, subagents, and runtime skills do not receive snapshot storage paths or read snapshot files directly. Snapshot placement and persistence ownership are defined by [Central Persistence](central-persistence.md). Project instructions and capability skills are trusted project code, but the orchestrator invokes only capabilities allowed by the pinned bundle. Changes to `.kos/` do not affect an already started task.

## Version 1 Documents And Validation

The normative draft 2020-12 schemas are `schemas/project/v1/task-type.json`, `workflow.json`, and `bundle-manifest.json`, with shared definitions in `common.json`. Every document is closed, uses `schema_version: "1"`, and has no unspecified fields. A task type declares its stable `id` and a workflow pointer containing `id`, semantic `version`, and direct repository-relative `path`.

A workflow declares stable `id` and semantic `version`, `initial_status`, a separate `terminal_status`, executable `statuses`, and `transitions`. Every executable status declares `execution_mode` (`main_session` or `subagent`), one direct `.md` instruction path, direct material references, `allowed_capabilities`, `worktree` (`required` or `none`), `repository_changes` (`allowed` or `forbidden`), and `required_artifacts`. An instruction is UTF-8 Markdown. Each closed material reference contains repository-relative `.kos/...` `path` and `media_type`, which is either `text/markdown; charset=utf-8` or `application/yaml; charset=utf-8`. Material references do not recurse. Each artifact requirement declares `type`, `cardinality` (`one` or `many`), `subject` (`task` or `candidate`), and nonempty `allowed_states`. The terminal status is not an executable status and therefore has no instruction, attempt, materials, capabilities, repository policy, or artifact output contract.

Instruction and material files must be nonempty and valid UTF-8 after their exact-byte digests are computed. An instruction is at most 128 KiB, each material is at most 1 MiB, and one status's instruction and all of its materials total at most 4 MiB. Limits are measured in bytes, not characters, and match the executable CLI context limits. Material paths are unique within a status and cannot equal that status's instruction path.

Configuration loading uses Psych safe parsing with aliases disabled and inspects the YAML AST before conversion. It rejects duplicate mapping keys, aliases, custom tags, multiple documents, unknown schema fields, absolute or traversing paths, paths outside `.kos/`, any symlink in a referenced path, missing or non-file members, empty, invalid UTF-8, or oversized execution members, and task-type/workflow identity mismatches. A task-type workflow path must be exactly `.kos/workflows/<workflow-id>/<workflow-version>/workflow.yaml`. Validation also covers unique status IDs and edges, known endpoints, initial and terminal rules, reachability, outgoing edges for executable statuses, unambiguous decision branches, known capabilities, artifact type/state/subject compatibility, and agreement between status output requirements and transition conditions on every individual edge. Every source requirement must have an `artifact-present` or `artifact-state` condition, or an explicit `not-applicable` waiver, on each outgoing edge; `decision` is not evidence. Across the outgoing routes, every allowed artifact state must have an evidence-bearing route. A status that allows repository changes requires a worktree.

[ADR-0003](../decisions/0003-pinned-project-workflows.md) records the decision to use project-controlled, immutable snapshot bundles.

`kos-initialize` materializes the initial `.kos/` configuration, instructions, and materials from versioned assets as specified by [Initialization](initialization.md).
