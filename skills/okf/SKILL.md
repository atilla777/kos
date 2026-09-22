---
name: okf
description: Read or change product behavior specifications in the exact project worktree's specs/ Open Knowledge Format v0.2 bundle while preserving metadata, links, indexes, and unrelated content.
---

# Product Specifications In OKF

Use this skill whenever a workflow step reads or changes the product behavior
source of truth in a project's `specs/` directory. The bundle follows Open
Knowledge Format (OKF) v0.2. It describes goals, actors, user scenarios, rules,
errors, edge cases, acceptance criteria, and non-goals; it is not a technical
task plan, execution report, or copy of architecture and testing documents.

## Boundary

Require the exact project worktree from the caller. Resolve its `specs/`
directory and read or write only paths below that directory. Refuse a symlinked
bundle root, a path that escapes the bundle, another checkout, or an ambiguous
worktree. Repository files outside `specs/` may be read as evidence but must
not be edited through this skill.

KOS and its task artifacts remain outside the bundle. Do not call the KOS CLI,
change task state, edit workflow artifacts, commit, or push.

## Read Progressively

Read `specs/index.md` first. Use its descriptions to select only concepts
relevant to the current work, then follow standard Markdown links as needed.
The concept ID is its path relative to `specs/` without the `.md` suffix.

Treat the bundle as product knowledge, not proof that implementation or a check
exists. Verify implementation claims against repository evidence. Missing
optional metadata, unknown types, unknown fields, and broken links do not make
an otherwise conformant bundle unreadable.

## Find Affected Concepts

Before editing, search the complete bundle by concept path, title, description,
resource, tags, links, and relevant product terms. Follow index entries and
incoming links. Update every concept whose product meaning changes, but do not
rewrite concepts merely for style.

If no concept covers changed product behavior, create the smallest suitable
concept. For KOS product behavior use the descriptive type
`Product Specification`; OKF has no central type registry. Do not create a
concept for an implementation plan, code structure, test strategy, task
artifact, or transient result.

## Conformance

Every UTF-8 `.md` file below `specs/`, except reserved `index.md` and `log.md`,
is one concept and must begin with parseable YAML frontmatter delimited by
`---`. Its only universally required field is a nonempty string `type`.
Recommended fields are `title`, `description`, `resource`, and `tags`, but none
is required. Lifecycle fields such as `status`, `generated`, `verified`, and
`stale_after` are optional and must never be invented merely to fill a schema.

Unknown frontmatter fields are valid extensions. Preserve every unknown field,
its value, and all unrelated body content when updating a concept. Parse and
merge frontmatter rather than replacing it from a template. Do not reorder or
normalize unaffected metadata unless a repository formatter requires it.

`index.md` is a progressive-disclosure listing, not a concept. A root index may
have frontmatter containing `okf_version: "0.2"`; no other index has
frontmatter. Group entries under headings and use standard Markdown links with
the linked concept's short description. Keep each affected directory index
accurate when concepts are added, moved, renamed, deprecated, or materially
retitled.

`log.md` is optional and is not a concept. When present, preserve its flat,
newest-first groups headed by ISO `YYYY-MM-DD` dates and update it consistently
with the existing bundle convention.

Use standard Markdown links. Prefer bundle-relative links beginning with `/`
between concepts, for example `/workflows/development.md`. Explain the
relationship in surrounding prose because OKF links are untyped. Use ordinary
relative links for repository documents outside `specs/`.

## Product Specification Shape

For a `Product Specification`, use only the sections needed from this set:

- Goal
- Actors
- User Scenarios
- Rules
- Errors
- Edge Cases
- Acceptance Criteria
- Non-goals

Link to `docs/architecture.md`, `docs/testing.md`, or other technical contracts
when they are relevant. Do not duplicate their implementation boundaries,
test-layer rules, commands, or execution evidence into the product concept.

## Evidence And Uncertainty

Base changes only on the approved request, existing product specifications,
and observed repository evidence. Never infer a product requirement solely
from current implementation, fill a gap with a plausible assumption, or claim
that behavior, checks, publication, or verification occurred without evidence.

When sources conflict, preserve the conflict and ask one precise product
question through the calling workflow. If uncertainty is not material, make
the smallest evidence-supported change and state its basis in the caller's
artifact, not in the product specification.

## Verify

Before returning:

1. Enumerate every Markdown file below `specs/` and verify the reserved-file
   rules and each concept's parseable frontmatter with a nonempty string `type`.
2. Verify each changed index entry and all changed links resolve as intended.
3. Compare edited concepts with their prior bytes and confirm unknown metadata
   and unrelated sections remain present and unchanged.
4. Confirm the bundle contains product behavior only and that technical plans,
   task state, and unverified claims were not introduced.
5. Run the project's required checks when the workflow step grants that
   authority, and report their actual result to the caller.
