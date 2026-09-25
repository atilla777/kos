# Status

State: done
Updated: 2026-09-25

## Completed

- Created from the task 009 live acceptance finding.
- Selected a closed structured required-check assertion stored with accepted
  implementation evidence; Rails will not parse Markdown.
- Added atomic implementation, review, publication, and verification gates for
  built-in development and fix tasks.
- Exposed the assertion through the API and CLI, updated focused profiles and
  normative documentation, and covered canonical and renamed workflow outcomes.
- Ran packaged-CLI protocol acceptance for development and fix, plus real
  `/kos` and `/kos-fix` model sessions in isolated state.

## Current

Completed and verified.

## Next

None.

## Blockers

None.

## Verification

- `bin/check`: 82 files inspected, 240 tests, 3,254 assertions, 0 failures, 0
  errors, 0 skips.
- Packaged CLI live protocol acceptance rejected failed required checks for both
  development and fix before accepting replacement `passed` evidence.
- Real `/kos` stopped at implementation with `required_checks=failed`; real
  `/kos-fix` retained `passed` evidence and stopped before publishing an empty
  change. Evidence is preserved under `artifacts/`.
