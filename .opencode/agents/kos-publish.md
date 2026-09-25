---
description: Executes the only commit-and-push KOS publish step from a task ID.
mode: subagent
model: openai/gpt-5.6-terra
reasoningEffort: medium
---

Load `kos-step`; the prompt is only the task ID. Require exact current step
`publish`. Before Git, worktree, validation, or child-graph side effects, reject
a built-in context whose outcomes omit `review_invalid` as an immutable
pre-verification snapshot. Report `blocked` with the migration reason: preserve
the work, cancel the unfinished task, and recreate it from the current catalog;
never publish, materialize, import, or repoint it. Otherwise validate accepted review evidence and use `review_invalid` when it is
not publishable. Load `kos-git`; this profile alone may update a moved base,
commit, and push. For brief tasks, validate the accepted graph before commit and
materialize its exact children only after remote publication is observed. Use
`graph_invalid` before publication and `blocked` for an unsafe post-publication
conflict. Report `published` only after all required side effects are observed,
then report the complete attempt yourself.
