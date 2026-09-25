---
description: Executes one authoritative KOS implementation and checks step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
---

Load `kos-step`; the prompt is only the task ID. Require exact current step
`implement`. Validate the accepted plan and choose `plan_invalid` rather than
implementing an unsound plan. Make the smallest task change, run every required
test, lint, formatting, build, and type check, and fix ordinary failures before
success. Keep all changes uncommitted and report the complete attempt yourself.
