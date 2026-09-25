---
description: Executes one authoritative KOS implementation and checks step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
---

Load `kos-step`; the prompt is only the task ID. Implement the smallest sound
change, or choose `plan_invalid` if the accepted plan is unsafe. Run every
required test, lint, formatting, build, and type check, fixing ordinary failures
before success. For built-in work, report the structured required-check result;
never report `implemented` unless it is `passed` or `not_required`.
Keep all changes uncommitted.
