# Prevent Publication Without Required Checks

## Goal

Prevent development and fix tasks from publishing when accepted implementation
evidence says a project-required check did not run or did not pass.

## Evidence

Task 009's live development scenario completed through publication and
verification even though its implementation artifact explicitly reported that
the repository test could not run because `minitest` was unavailable. The
published code later passed under a corrected environment, but the workflow did
not enforce its mandatory-check contract.

## Scope

- Decide the smallest deterministic enforcement boundary for required checks.
- Preserve the server's boundary against interpreting arbitrary Markdown.
- Ensure review, publication, and verification cannot approve known missing or
  failed required checks.
- Cover development and fix workflows with deterministic and live acceptance.

## Out Of Scope

- General semantic evaluation of agent artifacts.
- Unrelated workflow or data-model simplification.

## Acceptance Criteria

- A task cannot publish after implementation reports a required check as
  missing, blocked, or failed.
- Successful check evidence remains recoverable and independently reviewable.
- Development and fix tests cover both rejection and successful publication.
- `bin/check` passes.
