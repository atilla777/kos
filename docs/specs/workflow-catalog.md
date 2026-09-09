---
title: KOS Workflow Catalog
status: active
---

# KOS Workflow Catalog

## Ownership

The central Rails application owns shared task types, workflow drafts, and published workflow versions in SQLite. A target Git repository does not contain an authoritative `.kos` workflow configuration. Every catalog read or mutation goes through the Ruby CLI and versioned Rails API.

One task type has one workflow family and selects one current published version for new tasks. The operational MVP provides the shared `quick-fix` task type. All registered repositories use that selection; repository-specific assignments are deferred.

## Drafts And Publication

A workflow draft is mutable authoring state. It contains the complete proposed graph and execution content and has an optimistic lock version. Draft import replaces the complete draft document rather than applying partial edits to individual instructions or transitions.

Publication is authenticated, idempotent, and atomic. It validates the complete draft and creates one immutable version containing:

- stable workflow identity and semantic version;
- initial executable state and one terminal state;
- executable states and their execution modes;
- one nonempty UTF-8 Markdown instruction per executable state;
- optional nonempty UTF-8 Markdown artifact templates;
- worktree and repository-change policy;
- an allowlist of typed repository effects;
- required artifact contracts; and
- transitions and typed conditions.

A published version has a stable immutable identifier and a content digest over its canonical export document. The digest supports import/export comparison and does not replace the identifier inside one KOS installation. Published versions and their child records cannot be updated or deleted. Correcting any content requires another semantic version.

Activating a version atomically changes the task type's current-version reference. The version must be published for that task type. Existing tasks retain their original `workflow_version_id`; only later task creation observes the new current version. An active task cannot migrate between versions in version 1.

## Workflow Language

Executable states are distinct from the terminal state. Each executable state declares a stable identifier, execution mode (`main_session` or `subagent`), instruction, optional artifact templates, required artifacts, worktree policy, repository-change policy, and allowed repository effects. The terminal state has no instruction, attempt, template, effect, or output contract.

The language has no arbitrary expressions or Ruby code. A transition condition is one of `always`, `artifact-present`, `artifact-state`, `decision`, or `not-applicable`. Multiple conditions are conjunctive. The artifact evidence and waiver semantics are defined by [Workflow Execution](workflow-execution.md).

The initial version allows the typed repository effects required inside an executable workflow-step session: worktree removal, commit, fetch, rebase, and push. Worktree creation remains a pre-context orchestrator allocation operation and cannot be published as a workflow-step effect. A workflow instruction cannot add an effect. `kos-repository` remains the only executor of mutating Git operations.

## Validation

Draft validation and publication reject unknown fields, malformed identifiers or versions, empty or invalid UTF-8 content, duplicate state or template identifiers, duplicate edges, unknown endpoints, an executable terminal state, a transition leaving the terminal state, an unreachable state, a nonterminal state without an outgoing transition, ambiguous decision branches, incompatible artifact type/state/subject combinations, inconsistent transition evidence, and repository changes without a required worktree.

Every required artifact from a source state must have evidence or an explicit `not-applicable` waiver on each outgoing edge. Across outgoing routes, every allowed artifact state must have an evidence-bearing route. `always` must be the sole condition and is valid only when the source has no required artifact output.

An instruction is at most 128 KiB, each template is at most 1 MiB, and one state's instruction plus templates total at most 4 MiB, measured as UTF-8 bytes. These limits bound executable context size rather than database capacity.

Database constraints protect identifiers, foreign keys, local uniqueness, published-version immutability, task/version relationships, and state membership. Whole-graph validation belongs to the publication domain operation and runs before any published row becomes visible.

## Read And Export

Catalog list and get operations are authenticated global reads rather than repository-scoped reads. Export returns a closed canonical document containing the complete published version. It contains inline instruction and template content and no database IDs except the public workflow-version identifier, storage paths, or task state.

Import and export are interchange boundaries, not alternate sources of truth. Files used to prepare or receive an import or export do not become live project configuration.

[ADR-0007](../decisions/0007-central-workflow-catalog.md) records this ownership and immutability decision.
