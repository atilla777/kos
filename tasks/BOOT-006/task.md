---
title: Repository-Native Normative Specification
task: BOOT-006
created: 2026-09-08
---

# BOOT-006: Repository-Native Normative Specification

## Goal

Make Git the sole source of normative KOS requirements by moving the temporary high-level specification from Obsidian into focused repository specifications, rules, and architecture decisions.

## User Outcome

KOS requirements, invariants, and accepted architecture decisions are discoverable and reviewable with the code. Runtime behavior does not change.

## Context

The normative high-level specification currently remains in a temporary Obsidian note. The repository already contains engineering rules and ADR-0001, but no domain specifications, so the source must be decomposed without duplicating existing contracts or losing deferred requirements.

## Requirements

- BOOT-006-REQ-001: Preserve every normative requirement from the temporary high-level specification in an appropriate repository specification, rule, or ADR.
- BOOT-006-REQ-002: Separate observable domain and integration contracts from engineering rules and architecture rationale.
- BOOT-006-REQ-003: Avoid duplicating contracts already established by repository rules or ADR-0001; use links where one source should reference another.
- BOOT-006-REQ-004: Preserve the initial quick-fix MVP boundary and identify post-MVP capabilities as deferred rather than current implementation commitments.
- BOOT-006-REQ-005: Update documentation indexes and repository references so the migrated contract is discoverable.
- BOOT-006-REQ-006: Remove the temporary Obsidian specification only after checking that its complete normative content has a repository destination.

## Scope

- Add focused domain specifications for the product boundary, task model, workflow execution, artifact contracts, repository isolation, publication, project configuration, runtime integration, and initialization.
- Add ADRs for accepted long-lived architecture decisions not adequately captured by ADR-0001.
- Refine engineering rules only where the temporary specification contains a durable implementation constraint not already represented.
- Update repository documentation indexes and the external bootstrap dashboard.
- Delete the temporary Obsidian specification after migration verification.

## Non-Goals

- Implementing models, persistence, API endpoints, CLI commands, workflow schemas, skills, or runtime adapters.
- Defining the detailed versioned JSON schemas, command payloads, or error response shapes assigned to BOOT-007.
- Defining the detailed `.kos` YAML schema or canonical bundle digest algorithm assigned to BOOT-008.
- Changing accepted product behavior or architecture.
- Starting BOOT-007 in this session.

## Related ADRs

- [ADR-0001: Central REST API and Multi-Repository State](../../docs/decisions/0001-central-rest-api.md)

## Task-Local Decisions

- BOOT-006-DEC-001: Organize observable contracts by stable domain boundary rather than preserving the temporary specification as one monolithic repository document.
- BOOT-006-DEC-002: Keep detailed schemas and algorithms at the level already accepted by the high-level contract; later technical-contract tasks will make them implementation-ready.
- BOOT-006-DEC-003: Treat the source-note deletion as part of acceptance, not as cleanup before migration verification.

## Acceptance Criteria

- BOOT-006-AC-001: Every normative section of the temporary high-level specification is represented by a repository specification, rule, ADR, or an explicit link to an existing source.
- BOOT-006-AC-002: Repository indexes link to every added specification and ADR and no longer state that domain specifications are absent.
- BOOT-006-AC-003: The migrated documents preserve the quick-fix MVP boundary and distinguish deferred capabilities.
- BOOT-006-AC-004: The Obsidian dashboard no longer links to the temporary specification and the source note is deleted after verification.
- BOOT-006-AC-005: Documentation and project checks pass, and the completed change is committed and pushed to the default branch.

## Implementation Plan

1. Record this approved task baseline.
2. Map each source section to its existing or new normative repository destination.
3. Add focused specifications and ADRs, refining rules only where necessary.
4. Update indexes and cross-references without duplicating normative contracts.
5. Verify every source section against its destination, then remove the temporary Obsidian note and its dashboard link.
6. Run documentation and project checks.
7. Commit and push the repository changes.
8. Record completion externally and leave BOOT-007 as the next task.

## Verification

- Review all twelve source sections and the MVP criteria against their repository destinations.
- Verify repository Markdown links and remaining Obsidian wiki links resolve.
- Run `git diff --check`.
- Run `mise run lint`.
- Run `mise run check`.
- Allow configured commit and push hooks to run without bypassing them.

## Risks

- BOOT-006-RISK-001: Decomposing a long source can omit a requirement. Use a section-by-section destination review before deleting it.
- BOOT-006-RISK-002: Repeating one invariant in several documents can create conflicting sources. Keep one normative statement and cross-reference it from adjacent domains.
- BOOT-006-RISK-003: Adding implementation detail now could pre-empt BOOT-007 or BOOT-008. Preserve only the accepted high-level contract and explicitly defer detailed schemas and algorithms.
