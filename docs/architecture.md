# Architecture Rules

These rules govern implementation decisions in this repository.

## Boundaries

- Rails owns persistent state, validation, and transactional transitions.
- The CLI is a thin HTTP client and never reads SQLite directly.
- Skills own orchestration, substantive work, artifacts, checks, review, and
  Git operations.
- The file system owns current uncommitted work and Markdown artifacts.
- Git owns published commits and their SHA values.
- No hidden daemon, runtime broker, or general workflow engine is introduced.

## Design Rules

- Add a mechanism only when the end-to-end scenario requires it.
- Keep the REST API and CLI protocol small and explicit.
- Enforce state invariants at the server boundary and inside transactions.
- Prefer database constraints in addition to model validation where practical.
- Derive machine-local paths; do not persist them as domain state.
- Treat workflow definitions as immutable values after first use.
- Keep external side effects outside Rails transactions.
- Recover uncertain external operations by observation before retrying them.
- Never create a task commit before the publication step.
- Keep concrete model identifiers in OpenCode agent configuration, not workflow
  or task state.
- Keep product behavior in the repository's `specs/` OKF bundle, technical
  design in `docs/`, and execution evidence in external task artifacts.

## Current Foundation

At `PLAN-012`, Rails exposes the required administrative and task lifecycle
operations through a small bearer-authenticated JSON API while its readiness
endpoint remains public. Explicit response projections include each task's
snapshotted workflow and current step; known request, validation, transition,
ownership, and lookup failures have stable JSON errors. Pre-claim task
definition edits replace description, parent, and blockers atomically. The
lifecycle layer creates, edits, claims, resumes, transitions, pauses, completes,
and cancels tasks while fencing stale owners and repeated reports. Development
and production SQLite databases live in the configured local KOS data directory
outside the repository, and lease duration is configured by
`KOS_LEASE_SECONDS`. A thin, stateless `kos` HTTP client is distributed as a
Ruby gem, exposes every current API operation, reads workflow JSON and task
Markdown from files or standard input, preserves server responses, and reports
local or transport failures as structured errors. A distributable OpenCode Git skill derives task worktree
paths from the configured KOS data home, isolates uncommitted task work, and
defines observation-driven base-update, publication, and interruption-recovery
procedures. It uses Git directly and adds no Git API, wrapper, broker, or
persisted Git state to Rails. Integration scenarios with isolated persistent
databases, data directories, Git repositories, and bare remotes verify restart
and lost-response recovery, parallel task isolation, moved-base repetition of
checks and read-only review, and observation-driven publication recovery without
duplicate commits. The `/kos` OpenCode command loads a CLI-only orchestrator
skill, which verifies ownership before each step and delegates exactly one step
to a fresh standard- or advanced-tier executor. Before dispatch the orchestrator
removes a safe regular current Markdown artifact, then the executor writes a new
file directly at that path before returning its outcome. The orchestrator
verifies the exact response and artifact bytes before reporting; file identity
is irrelevant. Independent review remains
read-only for the worktree while writing `review.md`. Concrete models live in
OpenCode agent profiles, not Rails. Uncertain reports recover by observing
server state. No artifact state or orchestration runtime is added to Rails.
A single real `/kos` invocation creates and develops a task, checks it with
`bin/check`, obtains independent read-only review, publishes one verified
commit, and completes the task.

`PLAN-014` adds stable unique task type keys. Its migration assigns existing
types deterministic non-reserved keys without inferring identity from display
names and rejects partial or reserved-key states. Database seeds transactionally
install the canonical `brief`, `development`, and `fix` catalog. Reruns reuse an
identical current definition or create a new immutable workflow row and repoint
only the built-in type, so existing task snapshots and custom catalog entries
remain unchanged. `PLAN-015` adds type-key task creation and filtered
next-claim, exact task claim, owner-idempotent atomic create-and-claim, owned
task observation, and resumable selection through the Rails API and thin CLI.
A partial unique database index enforces that one nonempty owner identifies at
most one task. Numeric task type IDs remain available for administrative
compatibility. `PLAN-016` adds canonical read-only brief graph validation,
fenced transactional materialization, and complete child observation through
the API and CLI. Local batch keys are canonicalized to deterministic positions,
so observation can reproduce the validated digest without adding persisted
graph state. Every child snapshots the current development workflow and is
blocked by its brief parent plus declared siblings. Public lifecycle operations
cannot add or redefine brief children outside materialization, preserving the
reviewed graph until those tasks are claimed. `PLAN-017` adds the confined
`okf` OpenCode skill and this repository's minimal `specs/` bundle. The skill
preserves unknown metadata and unrelated content while maintaining links and
indexes; Rails does not parse or store OKF. OpenCode command changes remain
later-plan work. `PLAN-018` makes `/kos` a development-only command using the
stable built-in key. It discovers resumable development work before claiming a
pending task, retains human answers in restart-safe step sidecars, runs planning
through a dedicated read-only advanced agent, and follows `plan`, `implement`,
`document`, `review`, and `publish` without a separate built-in check step.
`PLAN-019` adds `/kos-fix`: an exclusively published request-bound command
intent and durable task receipt protect atomic fix creation from concurrent
invocations and lost responses. A dedicated advanced diagnosis agent reproduces
the symptom and establishes an evidenced root cause without changing the
worktree before the existing planning and delivery path runs.
`PLAN-020` adds `/kos-brief`: durable request creation leads into main-agent
product clarification through `okf`, while an isolated advanced agent reviews
both the `specs/` diff and exact proposed graph bytes. The orchestrator validates
that reviewed graph through the existing read-only server operation before an
isolated publisher commits and pushes only the specification. After observed
remote success it atomically materializes the retained graph, recovers an
ambiguous response by observing all children, and completes the brief only
after the graph is proven. Rails gains no specification or review state.
`PLAN-021` adds an idempotent OpenCode integration installer and proves a clean
installation against an isolated Rails database, installed CLI gem, OpenCode
configuration, fixture repository, and bare remote. Real `/kos-brief`, `/kos`,
and `/kos-fix` invocations publish three single task commits and finish with
completed tasks, released ownership, and durable artifacts. OpenCode 1.18.26
cannot apply path-scoped edit permissions to its `apply_patch` tool, so
diagnosis, planning, and review profiles permit that tool to write their
external artifacts; their worktree read-only boundary is enforced by the step
contract and by the orchestrator's exact HEAD and status comparisons before and
after each attempt.
`PLAN-022` adds canonical repository identity without replacing numeric project
or task IDs. Rails stores and uniquely indexes `host/namespace/repository`, while
`kos-git` validates one `origin` fetch/push identity and `kos-cli` performs the
exact project lookup. Administrative rename or transfer updates the existing
project row, preserving task associations and derived worktree paths.

## Built-In Scenario Target

The next version installs three global built-in task types identified by stable
machine keys: `brief`, `development`, and `fix`. Bootstrap is idempotent. A
changed canonical definition creates a new immutable workflow row and repoints
only its built-in type; existing tasks retain their snapshotted workflow.
Projects and custom workflow definitions remain administrative concerns.

Rails continues to know only task types, immutable workflow definitions,
ownership, dependencies, and transitions. It adds typed selection, exact claim,
idempotent create-and-claim by unique owner, resumable-task observation, and
atomic brief-child materialization as explicit state operations, but does not
learn how to plan, diagnose, check code, interpret OKF, run agents, or publish
Git changes. Child materialization is fenced by the brief ownership and current
publication point and is recovered through a read-only graph projection.

The CLI remains a stateless transport for every server operation. User-facing
skills select built-ins by stable key, not numeric `KOS_TASK_TYPE_ID`. The
server and CLI do not choose which OpenCode process or model executes a step.

Command orchestration is split by user intent:

- `/kos` takes the next available `development` task and accepts no task text.
- `/kos-fix <problem>` creates and exactly claims one `fix` task.
- `/kos-brief <request>` creates and exactly claims one `brief` task.

Development and fix steps use fresh isolated agents. Advanced read-only agents
perform `plan` and `diagnose`; an implementation agent changes code and runs all
required project checks; a documentation agent uses `okf`; another advanced
read-only agent performs `review`; and the publication agent alone may commit
or push. A moved base returns to `implement`, so checks, documentation, and
review all repeat. The built-in workflows have no separate `check` step, but
the generic workflow validator does not reserve or reject that ID.

Brief elaboration runs in the main conversational agent rather than a one-shot
step agent. This preserves questions, user answers, repository context, the OKF
change, and the proposed child graph in one orchestration. Review and
publication still use independent isolated agents. The orchestrator validates
the reviewed graph without mutation before publication. After publication is
observed, it materializes that graph and reports the publication outcome only
after the graph is observed. `complete` and `materialize` are not executable
workflow steps.

Graph validation persists no server-side gate. It returns a digest of the
canonical definition; the orchestrator retains the reviewed bytes and digest,
and passes that expected digest to materialization. The server transactionally
revalidates and compares the digest before inserting children. The orchestrator
also blocks before the request when its retained bytes differ. Rails remains
responsible for current database invariants, not for remembering review
evidence.

Command skills persist a non-secret local intent before an atomic create and
claim. The unique owner ID makes retries idempotent and lets a restarted command
observe the created active task without exposing an internal ID. Commands query
resumable tasks of their own built-in type before starting new work. Human
answers are atomically preserved in step-specific sidecars before resume, so a
second process interruption does not discard them. This recovery state remains
in the data home and never becomes Rails domain state.

The shared `okf` skill operates only on `specs/` in the supplied task worktree.
It preserves unknown frontmatter and unrelated content, maintains concept links
and indexes, and never infers product requirements from implementation details.
Rails stores no OKF documents or lifecycle status. `docs/architecture.md` and
`docs/testing.md` remain technical contracts, while `plan.md`, `diagnose.md`,
`implement.md`, `document.md`, `review.md`, and `publish.md` remain external
execution artifacts.

These target boundaries are normative even while `PLAN-014` through `PLAN-021`
implement and prove them incrementally. The current foundation above describes
what has already been demonstrated; it is not permission to expose partially
implemented built-in scenarios as ready.

See [the product specification](specification.md) for the complete product
contract.
