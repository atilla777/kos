# Status

State: done
Updated: 2026-09-25

## Current

Implemented terminal publication and removed the built-in verifier.

## Completed

- Built-in brief, development, and fix workflows now complete only from
  `publish` with `published`, after existing check and brief graph gates.
- Removed verifier scheduler dispatch, profile source, and installed inventory;
  the installer removes an obsolete installed `kos-verify.md`.
- Updated lifecycle, catalog, graph, scenario, package, profile, and acceptance
  tests for terminal publication.
- Updated normative product, protocol, architecture, testing, installation, and
  README contracts, including the trusted shared-token and concurrency-only
  owner/fence model.
- Added no legacy workflow support or migration and left graph APIs and
  single-commit publication unchanged.
- Independent review found and corrected the unsafe in-place upgrade wording
  and the final non-historical `verify` fixture.

## Blockers

None.

## Verification

- Focused tests: 99 runs, 1,996 assertions, 0 failures, 0 errors.
- `bin/check`: 82 files linted with no offenses; 240 runs, 3,170 assertions,
  0 failures, 0 errors.
