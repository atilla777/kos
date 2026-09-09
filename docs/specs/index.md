---
title: KOS Domain Specifications
status: active
---

# KOS Domain Specifications

These documents are normative specifications of observable KOS behavior and material integration contracts.

| Document | Scope |
| --- | --- |
| [Product Boundary](product-boundary.md) | Purpose, first-version boundary, operational MVP, and deferred capabilities |
| [Task Model](task-model.md) | Task types, tasks, public numbers, traceability, and relations |
| [Workflow Execution](workflow-execution.md) | Workflow semantics, attempts, ownership, orchestration, and deferred workflows |
| [Artifact Contracts](artifact-contracts.md) | Immutable evidence, transition validation, and candidate generations |
| [Repository Isolation](repository-isolation.md) | Repository scope, task worktrees, reservations, and Git ownership |
| [Publication](publication.md) | Reviewed candidates, fast-forward publication, and recovery |
| [Project Configuration](project-configuration.md) | Project-owned `.kos` configuration, versioning, and pinned bundles |
| [Runtime Integration](runtime-integration.md) | Canonical skills, runtime targets, and CLI protocol |
| [CLI Protocol Version 1](cli-protocol.md) | Versioned commands, JSON schemas, transport, preconditions, and stable errors |
| [Initialization](initialization.md) | Safe target-project and runtime installation |
| [Central Persistence](central-persistence.md) | Production state layout, migrations, snapshot storage, and repository registration |

Create or update a focused specification with any durable behavior change. Do not place implementation plans, private class design, detailed schemas assigned to later technical-contract tasks, or transient agent notes here.
