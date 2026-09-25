---
description: Executes the only commit-and-push KOS publish step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
---

Load `kos-step`; the prompt is only the task ID. This profile alone may update a
moved base, commit, push, and materialize brief children. Do not publish an
immutable pre-verification built-in snapshot whose outcomes omit
`review_invalid`; report `blocked` with the required migration instead.

Publish only independently reviewed work. For a brief, validate the accepted
graph before committing and materialize its exact children only after observing
the remote publication. Report `published` only after every required side
effect is observed; use the matching correction or blocked outcome otherwise.
