---
title: Repository-Specific Task Prefixes
status: accepted
date: 2026-09-09
---

# ADR-0006: Repository-Specific Task Prefixes

## Context

KOS serves multiple Git repositories, but the original public task-number contract used the same `TASK-` prefix for every repository. A number such as `TASK-000123` therefore needed separate repository context even though public numbers also appear in documents, paths, branches, Git trailers, and human communication.

## Decision

Each registered repository has a human-selected `task_prefix`. It is globally unique within one KOS installation, immutable after registration, and consists of 2 through 10 uppercase ASCII letters or digits beginning with a letter. Input must already be uppercase; KOS does not silently normalize it.

A task's public number combines that prefix with its six-digit repository-local numeric sequence, for example `KOS-000123`. Initialization presents the exact prefix for human confirmation together with the repository path and trust settings. Registration rejects an occupied prefix and treats a changed prefix for an existing repository as a conflict.

The complete observable contract is defined by [Task Model](../specs/task-model.md) and [Central Persistence](../specs/central-persistence.md).

## Consequences

- A public task number identifies one repository and task within a KOS installation without separate repository context.
- Existing task references remain stable because the repository prefix cannot change.
- Preferred abbreviations can conflict across repositories and require the user to select another prefix.
- The database stores the repository prefix and repository-local numeric sequence separately; formatting belongs at the application and transport boundaries.
- Public-number consumers must accept the repository-specific prefix rather than hard-code `TASK-`.

## Rejected Alternatives

### Keep the fixed `TASK-` prefix

This leaves public identifiers ambiguous across repositories and weakens their value in Git and human communication.

### Allow duplicate prefixes

This would still require repository context to resolve a public number.

### Derive and normalize a prefix automatically

Repository names are not guaranteed to be stable or unique. Silent normalization can also make the confirmed identifier differ from user input.

### Allow prefix changes for future tasks

Maintaining old and new namespaces for one repository adds history and lookup rules without a current need.
