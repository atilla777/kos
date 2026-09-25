# Simplify Git Publication

## Goal

Replace the detailed model-executed Git protocol with a practical publication
flow, moving deterministic mechanics into code only when evidence justifies it.

## Scope

- Shorten Git and publication guidance.
- Preserve no-force publication and remote observation.
- Preserve existing work on base movement or interruption.
- Decide from observed complexity whether focused CLI publication operations are
  necessary.

## Out Of Scope

- General workflow or database redesign.
- Adding speculative Git recovery mechanisms without a reproduced need.

## Acceptance Criteria

- Publication instructions focus on desired result rather than command grammar.
- A normal reviewed task can be committed, pushed, and observed remotely without
  permission-pattern machinery.
- Interrupted or moved-base cases fail safely or recover from observed state.
- Any new CLI automation is covered by executable Git tests.
- `bin/check` passes.
