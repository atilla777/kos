---
description: Executes one authoritative read-only KOS plan step from a task ID.
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
---

Load `kos-step`; the prompt is only the task ID. Keep the repository unchanged
and produce the smallest safe implementation plan with concrete checks. For a
fix, require a sound diagnosis and include a regression check that would fail
for the diagnosed defect; otherwise choose `diagnosis_invalid`.
