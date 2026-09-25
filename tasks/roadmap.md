# KOS Development Roadmap

This is the authoritative ordered list for development of KOS itself. Detailed
scope and progress live in each linked task directory. Task files are repository
development records and are not read by the KOS server or CLI.

## Active

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 013 | [Publish reviewed commit sequences](013-reviewed-commit-ranges/task.md) | active | 011, 012 |

## Planned

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 014 | [Run simplified live acceptance](014-simplified-live-acceptance/task.md) | planned | 011, 012, 013 |

## Completed

| ID | Task | Status | Dependencies |
| --- | --- | --- | --- |
| 001 | [Bootstrap the file workflow](001-bootstrap-file-workflow/task.md) | done | - |
| 002 | [Establish the server and CLI baseline](002-server-cli-baseline/task.md) | done | 001 |
| 003 | [Remove OpenCode permission policy](003-remove-opencode-permissions/task.md) | done | 002 |
| 004 | [Simplify request-bound task creation](004-simplify-task-creation/task.md) | done | 002 |
| 005 | [Rewrite the CLI skill](005-rewrite-cli-skill/task.md) | done | 004 |
| 006 | [Rewrite schedulers and commands](006-rewrite-schedulers-and-commands/task.md) | done | 003, 005 |
| 007 | [Simplify step agents](007-simplify-step-agents/task.md) | done | 006 |
| 008 | [Simplify Git publication](008-simplify-git-publication/task.md) | done | 007 |
| 009 | [Run live acceptance scenarios](009-live-acceptance/task.md) | done | 008 |
| 010 | [Prevent publication without required checks](010-enforce-check-evidence/task.md) | done | 009 |
| 011 | [Complete built-in tasks at publication](011-terminal-publication/task.md) | done | 010 |
| 012 | [Materialize brief graphs atomically](012-atomic-brief-materialization/task.md) | done | 011 |

## Future Decisions

- Reassess further server workflow and data-model reductions only after the
  simplified publication flow has been exercised in real sessions.
- Decide from observed failures whether Git publication needs a deterministic
  CLI operation.
