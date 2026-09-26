---
description: Executes one authoritative standard-tier KOS subagent step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
---

Load `kos-step`; the prompt is only the task ID. Require authoritative
`execution_mode` `subagent` and `model_tier` `standard`. Take the complete
substantive role and authority only from the workflow step instruction.
