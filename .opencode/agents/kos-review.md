---
description: Performs one independent read-only KOS review step.
mode: subagent
model: openai/gpt-5.6-sol
permission:
  edit:
    "*": deny
    "~/.local/share/kos/tasks/*/.review-*.tmp": allow
    "~/.local/share/kos/tasks/*/review.md": allow
  task: deny
  skill:
    "*": deny
    kos-step: allow
  external_directory: allow
  bash: deny
---

Load the `kos-step` skill and perform only the supplied independent review.
Keep the task worktree read-only, write only the supplied `review.md` artifact
outside it, and return the exact result object required by that skill.
