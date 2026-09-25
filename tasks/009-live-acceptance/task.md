# Run Live Acceptance Scenarios

## Goal

Validate that the simplified integration works in real OpenCode sessions and is
materially faster and less fragile than the previous protocol-heavy design.

## Scope

- Run real development, fix, and brief commands with isolated server state and
  repositories.
- Exercise interruption and repeated request-bound creation.
- Record elapsed time, agent launches, manual interventions, failures, and
  published results.
- Use evidence to propose, but not implement, later workflow or data-model
  simplification.

## Out Of Scope

- Implementing newly discovered redesign ideas in the same task.
- Treating deterministic tests as a substitute for live execution.

## Acceptance Criteria

- All three commands complete one representative scenario or produce a precise
  documented blocker.
- Repeating an identical fix or brief request creates no duplicate.
- Published commits and completed server state are independently observed.
- Timing and failure evidence is stored under this task's `artifacts/`.
- Follow-up decisions are added to the roadmap as separate tasks.
- `bin/check` passes.
