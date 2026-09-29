# KOS Development Guide

## Project

KOS is a local task tracker for AI agents. The first MVP consists of a Rails application with SQLite and a JSON REST API, plus a Ruby CLI gem. The server is the source of truth for tasks, dependencies, claims, leases, and Markdown artifacts; the CLI identifies projects from Git remotes and calls the API.

The agreed MVP scope and baseline contract are in [docs/mvp-specification.md](docs/mvp-specification.md). The current user-visible behavior of implemented features is documented in [docs/knowledge/index.md](docs/knowledge/index.md) and is the source of truth for those scenarios. Read both before planning or changing behavior. Resolve contradictions explicitly before implementation; section 17 of the MVP specification contains proposed defaults that are not yet approved requirements.

Keep the MVP small. Do not introduce agent orchestration, workflow engines, skills, Git automation, UI, MCP, distributed infrastructure, or generalized extension systems unless the specification is explicitly changed.

## Development Rules

- Implement in small, working vertical increments and prefer the smallest correct design.
- Keep business rules and invariants on the Rails server; the CLI must remain a thin client and must not duplicate task-availability or claim algorithms.
- Enforce critical uniqueness, foreign-key, ownership, lease, version, and dependency invariants in the database and transactional server operations, not only in Rails validations.
- Keep protected state transitions explicit. Ordinary updates must not bypass claim, renew, release, complete, or reopen operations.
- Test behavior on the actual SQLite configuration, including concurrent claims, lease expiry, stale owners, dependency cycles, artifact conflicts, transaction rollback, and ambiguous client failures.
- Preserve JSON stdout and stderr separation in the CLI, finite network timeouts, stable nonzero error exits, and machine-readable API errors.
- Never log or expose complete claim tokens, credentials, or access tokens embedded in Git URLs.
- Update documentation and tests together with behavior. Record any approved choice from specification section 17 before relying on it as a fixed contract.
- Do not add compatibility layers, abstractions, dependencies, or configuration without a concrete current requirement.

## Required Task Delivery Cycle

Every development task follows these stages in order. Track progress and evidence in its task note; a task is completed only after publication succeeds. These are rules for *developing KOS*, not new API states or agent-orchestration features of KOS itself.

1. **Plan:** agree on the problem, expected user outcome, scope, acceptance criteria, dependencies, affected user scenarios, and checks before implementation.
2. **Implement and test:** make the smallest change; write or adjust meaningful tests for changed behavior, run them and the relevant project checks, and record results. For documentation-only changes, run applicable documentation checks rather than adding artificial code tests.
3. **Review:** inspect the complete diff against the plan, acceptance criteria, tests, security and existing contracts; resolve findings and rerun affected checks. Record the review outcome in the task note. If later changes affect reviewed behavior, repeat the relevant review.
4. **Update documentation:** create or update Markdown concept documents under `docs/knowledge/` in [OKF v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) format. Describe the feature as users experience it: normal, alternative and error scenarios, observable results and limits; omit implementation details. Treat these documents as the source of truth for implemented user-visible behavior. For a task with no feature impact, inspect the affected concepts and record why no behavior change is needed. Keep `docs/knowledge/index.md` navigable and align the MVP specification when its lasting requirements change. Review documentation edits before publication.
5. **Publish:** inspect Git status and the full diff, stage only intended files without secrets or runtime data, commit, and push to `origin/main` on GitHub. Confirm the remote branch contains the commit; if publication fails, keep the task active and record the blocker. Do not force-push or overwrite unrelated work.

After any fixes introduced by review or documentation, rerun affected checks and review the final change before publishing. The task note records plan, verification, review, documentation impact, commit and publication result.

## Obsidian Tasks

Planning state is maintained in the Obsidian vault at:

`/home/aleksei/Yandex.Disk/obsidian-vault/B - работа Plums Lab/KOS`

Use these files as the task-planning source of truth until the user explicitly changes the process:

- `KOS.md`: project dashboard and current state.
- `KOS - roadmap.md`: agreed project outcomes, phases, and completion criteria.
- `KOS - backlog.md`: Active, Next, Later, Blocked, and the next free `PLAN-*` number.
- `KOS - inbox.md`: unprocessed ideas that are not tasks yet.
- `KOS - archive.md`: completed and cancelled tasks.
- `PLAN-NNN - <title>.md`: detailed scope and outcome of one task.

Follow this workflow:

1. Read `KOS.md`, roadmap, and backlog before planning or starting work.
2. Capture raw ideas in inbox. Do not turn an idea into a task until its problem, expected result, scope, and acceptance criteria are clear.
3. Assign task IDs sequentially from the next free number in backlog, starting with `PLAN-001`. Never reuse an ID already present in active files or archive.
4. Create a separate task note containing at least goal, in-scope work, out-of-scope work, acceptance criteria, dependencies, and relevant user decisions.
5. Keep at most one task in Active. Do not implement a task until its scope and acceptance criteria have been explicitly agreed with the user.
6. During work, keep the task note and dashboard accurate. Record blockers and concrete user decisions when they occur.
7. Follow the Required Task Delivery Cycle above and verify the acceptance criteria against the MVP scope and current user-facing documentation.
8. After successful publication, record the result and verification in the task note, move its summary to archive, remove it from active backlog sections, select the next task only when dependencies permit, and update `KOS.md`.
9. Keep lasting product requirements in repository documentation: current feature behavior in `docs/knowledge/`, and changes to MVP scope or baseline contract in `docs/mvp-specification.md`. Do not leave normative decisions only in Obsidian task notes.

Do not delete, renumber, or rewrite task history unless the user explicitly requests it.
