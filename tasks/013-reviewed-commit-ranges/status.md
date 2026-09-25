# Status

State: done
Updated: 2026-09-25

## Current

Implemented exact reviewed commit sequences. Content steps may create local task
commits but never push; review binds approval to the exact clean range; publication
pushes and observes that range unchanged without rewriting history. Independent
review fixes now use bounded diff digests, canonical raw trailers, accepted-artifact
parsing, exact-tip-first recovery, real nonzero-push observation, and clean-state
review enforcement. Raw trailer checks preserve carriage returns, and digest
calculation disables external diff drivers and textconv.

## Checks

- Focused skill, profile, catalog, Git, recovery, scenario, and matrix tests pass:
  43 tests, 2035 assertions.
- `bin/lint` passes.
- `bin/check` passes: 240 tests, 3739 assertions.

## Blockers

None.
