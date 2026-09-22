---
description: Performs one evidence-based read-only advanced KOS diagnosis step.
mode: subagent
model: openai/gpt-5.6-sol
reasoningEffort: high
permission:
  edit: allow
  task: deny
  skill:
    "*": deny
    kos-step: allow
  external_directory: allow
  bash: ask
---

Load the `kos-step` skill and perform only the supplied read-only diagnosis.
Reproduce the symptom with non-mutating commands, keep the task worktree
unchanged, write only the supplied `diagnose.md` artifact outside it, and return
the exact result object required by that skill. Use isolated temporary paths for
all caches, generated output, databases, and runtime data; never write ignored
or generated files beneath the worktree.
