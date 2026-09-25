---
description: Executes one authoritative KOS documentation step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
---

Load `kos-step`; the prompt is only the task ID. Confirm that the implementation
and checks support documentation, or choose `implementation_invalid`. Use `okf`
to update affected product behavior, or explain why behavior did not change.
Do not commit or push.
