# KOS Development Roadmap

This is the authoritative ordered list for development of KOS itself. Detailed
scope and progress live in each linked task directory. Task files are repository
development records and are not read by the KOS server or CLI.

## Active

None.

## Planned

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 002 | [Establish the server and CLI baseline](002-server-cli-baseline/task.md) | planned | 001 |
| 003 | [Remove OpenCode permission policy](003-remove-opencode-permissions/task.md) | planned | 002 |
| 004 | [Simplify request-bound task creation](004-simplify-task-creation/task.md) | planned | 002 |
| 005 | [Rewrite the CLI skill](005-rewrite-cli-skill/task.md) | planned | 004 |
| 006 | [Rewrite schedulers and commands](006-rewrite-schedulers-and-commands/task.md) | planned | 003, 005 |
| 007 | [Simplify step agents](007-simplify-step-agents/task.md) | planned | 006 |
| 008 | [Simplify Git publication](008-simplify-git-publication/task.md) | planned | 007 |
| 009 | [Run live acceptance scenarios](009-live-acceptance/task.md) | planned | 008 |

## Completed

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 001 | [Bootstrap the file workflow](001-bootstrap-file-workflow/task.md) | done | - |

## Future Decisions

- Reassess the server workflow and data model only after the simpler CLI and
  agent integration have been exercised in real sessions.
- Decide from observed failures whether publication needs a deterministic CLI
  operation.
- Consider merging workflow steps or profiles only with live timing and failure
  evidence.
