# Publish Reviewed Commit Sequences

## Goal

Allow content-producing agents to commit locally and publish every reviewed task
commit unchanged instead of requiring one publisher-created commit.

## Scope

- Allow brief, implementation, and documentation agents to commit but never push.
- Require a clean worktree and an ordered base-to-tip commit sequence at review.
- Require every task commit to contain its `KOS-Task` trailer.
- Make publication push the exact reviewed sequence without rewrite or squash.
- Recover ambiguous pushes by observing the remote sequence.

## Acceptance Criteria

- No task commit reaches the remote before publication.
- Review identifies the exact ordered commit sequence.
- Publication does not create, amend, rebase, squash, or cherry-pick commits.
- Every reviewed commit appears unchanged in remote history.
- Base movement returns work for integration and another review.
- `bin/check` passes.
