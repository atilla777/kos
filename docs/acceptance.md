# MVP Acceptance

Run the complete local verification from the repository root:

```bash
bin/ci
```

`bin/ci` runs style and security checks, all Rails and CLI tests, builds the CLI gem, and runs `script/acceptance`. The acceptance script installs the gem into an isolated temporary gem home and exercises the installed executable against a temporary Rails server and SQLite database.

## Scenario Coverage

| Specification | Automated evidence |
| --- | --- |
| 15.1 Main cycle | `script/acceptance` creates a task through Git discovery, claims it, writes an artifact, completes it, and confirms it is no longer ready. |
| 15.2 Independent clones | `script/acceptance` uses equivalent SSH and HTTPS remotes, verifies missing Git context and explicit `--project`; `cli/test/repository_test.rb` covers normalization and credential removal. |
| 15.3 Group and planning | `test/integration/task_groups_api_test.rb`, `test/models/task_group_test.rb`, and `test/integration/tasks_api_test.rb` cover computed group completion, atomic grouped task creation, blocked readiness, completion, and dependency artifacts in context. |
| 15.4 Concurrent claim | `test/models/task_claim_concurrency_test.rb` uses the configured SQLite database for competing sessions and parallel requests from one session. |
| 15.5 Expiry and old owner | `test/integration/tasks_api_test.rb` and `test/integration/task_artifacts_api_test.rb` cover reclaim, a new claim ID, computed expiry, and rejection of every stale write. |
| 15.6 Renewal | `test/integration/tasks_api_test.rb` covers identity-preserving renewal, reads without renewal, and the exact expiry boundary. |
| 15.7 Context recovery | `test/integration/restart_persistence_test.rb` starts a fresh application process and verifies persisted lease, summary, artifact, and UTC values; context integration tests verify reads do not alter results. |
| 15.8 Document conflict | `test/models/task_artifact_concurrency_test.rb` and `test/integration/task_artifacts_api_test.rb` cover stale updates and concurrent creation of one key. |
| 15.9 Graph correctness | `test/integration/tasks_api_test.rb`, `test/models/task_test.rb`, and `test/models/task_dependency_concurrency_test.rb` cover invalid edges, cycles, concurrent opposite edges, and transaction rollback. |
| 15.10 Transition protection | `test/integration/tasks_api_test.rb` and `test/integration/task_artifacts_api_test.rb` cover protected fields, claim requirements, explicit transitions, and immutable dependencies after work starts. |
| 15.11 Network and errors | `cli/test/client_test.rb`, `cli/test/command_test.rb`, and `test/integration/sqlite_contention_test.rb` cover finite timeouts, no mutation retries, ambiguous outcomes, error classes, JSON output, and `database_busy`. |
| 15.12 Product boundaries | `script/acceptance` verifies normal commands do not change branch, remote, or worktree state. Repository dependencies and runtime code contain no GitHub API, OpenCode, Redis, skill, MCP, UI, or workflow-engine integration. |
| 15.13 Step routing | `script/acceptance` creates a workflow with subagent and main steps, uses compact claim and a step packet, writes a result, advances, reads it as next-step input, and completes. `test/integration/workflow_api_test.rb` covers missing inputs, cross-project workflow, reclaim and stale transitions; `test/models/task_claim_concurrency_test.rb` covers competing advances. |
| Shared workflows | `test/integration/workflow_api_test.rb` covers global workflow creation and reuse across projects, visibility without registering a project, private project definitions and SQLite ownership triggers. The global-workflow migration is checked on a separate SQLite online backup of the existing local database with record counts and integrity checks, without migrating the original. |
| Ready-to-use workflows | `test/models/workflow_seed_test.rb` checks idempotent creation of three v1 definitions, replacement of unused definitions, rejection when a definition has tasks, and removal of unused v2 definitions. `test/integration/ready_workflows_test.rb` exercises the seeded Brief → blocked Execution handoff, publication gate, review/documentation instructions and a standalone Fix diagnosis; `script/test_install_opencode.rb` checks installation and discovery of agent instructions. Live agent conversations and verified publication remain a separate acceptance task. |

`script/acceptance` also runs a second installed-CLI cycle using a claim fingerprint instead of printing or passing the full claim; `cli/test/command_test.rb` verifies that a changed claim, missing current task, wrong step or read error stops the protected write before it is sent. Live OpenCode agent handoff and local transcript inspection are documented in the PLAN-016 acceptance record, not simulated by the CLI-only script.

The same acceptance script creates an online SQLite backup, restores it into a separate database while the server is stopped, and verifies the completed task. Temporary servers, databases, gems, repositories, and backups are removed after the run.
