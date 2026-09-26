# Plan

1. Update the normative product and architecture contracts for generic workflow
   execution, unrestricted `main` mode, two model tiers, CLI-owned session IDs,
   and the removal of role-specific dispatch.
2. Extend workflow validation, built-in definitions, and task context with
   `execution_mode`; define the effective mode for existing immutable workflow
   revisions and reject incompatible public updates to reserved task types.
3. Add local `kos session-id` and deterministic CLI tests for its
   format, uniqueness expectations, configuration independence, and help.
4. Replace role-specific OpenCode profiles with generic standard and advanced
   step profiles, then update installation cleanup and asset inventory.
5. Rewrite the shared scheduler and step guidance to execute `main` steps in the
   command agent, dispatch `subagent` steps only by tier, handle cancellation,
   and continue to recover exclusively from authoritative context.
6. Consolidate frequent invocation templates in `kos-cli`, remove mandatory
   per-operation help calls, and simplify `kos-brief` to avoid a duplicate
   scheduler layer.
7. Reduce `kos-git` to repository discovery, task worktree handling, and generic
   preservation rules; rely on workflow instructions for substantive Git roles.
8. Replace prompt-text dispatch tests with behavioral coverage for built-in and
   custom execution, especially built-in-name collisions and unrestricted main
   execution, while retaining ID-only subagent and fencing assertions.
9. Update README, installation, specification, architecture, and testing
   documentation; run `bin/check` and resolve every obsolete-profile or clean
   installation regression.
10. Complete the task records, commit, push without force, and independently
    observe the published commit and checks.
