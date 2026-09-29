---
name: kos-orchestrator
description: Use when orchestrating a KOS task in OpenCode from a compact claim/current route through step advancement and completion.
---

# Orchestrate KOS steps

Work in the target Git checkout, or set `KOS_PROJECT` to its canonical repository key. Use one stable `KOS_SESSION_ID` per independently working OpenCode session; do not invent a new identity on each CLI call or share one across concurrent sessions. The KOS server is the source of truth.

1. Run `kos task current --route` first to recover your existing claim. If `data.task` is null, run `kos task claim-next --route` (or `kos task claim ID --route`). If there is no ready task, stop. Inspect the JSON response's `data.task.id`, `data.task.claim_id`, `data.task.current_step`, and `data.task.step.executor`/`model_tier`. Do not fetch the full task or step package simply to decide who executes it.
2. For `executor: main`, run `kos task step show ID` yourself and do the instructed work. For `executor: subagent`, invoke only `kos-standard` for `model_tier: standard` or `kos-advanced` for `model_tier: advanced`. Pass the ID, canonical project key (or the target checkout), current step position, and the current claim securely in the subagent task invocation; no instructions, artifact contents, or full step packet. The subagent fetches the packet. Do not allow independent agents to work concurrently on the same claim.
3. Inspect the executor's result and any required checks according to the step instruction and project rules; KOS does not grade output. Renew a still-active claim with `kos --claim CLAIM task renew ID` when needed during long work (lease is 30 minutes). If lease expired or claim changed, stop protected writes, check `kos task current --route` and re-claim only if available; never reuse the old claim.
4. If another step remains, run `kos --claim CLAIM task advance ID --expected-step N` with the observed position. Read the new compact route with `kos task current --route` and repeat. On the final step, run `kos --claim CLAIM task complete ID --work-summary '...'` only after the required work is done. The main agent handles any publishing required by project instructions.

Use CLI JSON and exit status together: `0` with `data.task: null` means no work/current claim; `4` is a conflict (including `step_conflict`); `5` is `ambiguous_result`. On a conflict or ambiguous mutation, inspect `current --route`, `task show ID`, or the affected artifact before deciding whether to retry. Never blindly replay a mutation. Don't place full claim values in logs, artifacts, or user-facing reports.
