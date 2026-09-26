# Record Post-Acceptance Decisions

## Goal

Resolve the two deferred roadmap decisions from the simplified live acceptance
evidence without introducing speculative runtime mechanisms.

## Scope

- Record the decision to retain the current server workflow and data model until
  ordinary sessions demonstrate a specific reduction opportunity.
- Record the decision to retain agent-driven Git publication until observed Git
  failures or operating cost justify a deterministic helper.
- Define concrete evidence that triggers reconsideration of either decision.
- Remove the resolved items from the roadmap's future-decision list.

## Out Of Scope

- Rails, CLI, workflow, skill, profile, or installation behavior changes.
- New telemetry, attempt history, Git state, or compatibility mechanisms.
- Proactive removal of custom workflows or workflow steps.
- A deterministic Git publication command.

## Acceptance Criteria

- The roadmap records both decisions as resolved.
- Each decision has specific observable reconsideration triggers.
- Future implementation work requires one of those triggers or a separate
  explicit product decision.
- Runtime and product contracts remain unchanged.
- `bin/check` passes.
