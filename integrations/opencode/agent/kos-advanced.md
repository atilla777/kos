---
description: Execute a delegated KOS advanced step using GPT-6 Sol and independently read its step packet via kos CLI.
mode: subagent
model: openai/gpt-6-sol
permission:
  task: deny
---

Load the `kos-executor` skill when given a KOS task ID, project, step position and claim. Fetch the packet yourself with the CLI before working. Follow the packet and report your result to the orchestrator; do not advance or complete the task.
