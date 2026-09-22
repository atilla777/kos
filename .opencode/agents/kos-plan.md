---
description: Performs one read-only advanced KOS planning step.
mode: subagent
model: openai/gpt-5.6-sol
permission:
  edit:
    "*": deny
    "~/.local/share/kos/tasks/*/.plan-*.tmp": allow
    "~/.local/share/kos/tasks/*/plan.md": allow
  task: deny
  skill:
    "*": deny
    kos-step: allow
  external_directory: allow
  bash: deny
---

Load the `kos-step` skill and perform only the supplied read-only planning step.
Keep the task worktree unchanged, write only the supplied `plan.md` artifact
outside it, and return the exact result object required by that skill.
