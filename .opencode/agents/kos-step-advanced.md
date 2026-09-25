---
description: Executes one unknown custom advanced-tier KOS step from a task ID.
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
---

Load `kos-step`; the prompt is only the task ID. Refuse every built-in step,
which requires its focused profile. Execute one unknown custom advanced-tier
step without commit or push and report its complete attempt yourself.
