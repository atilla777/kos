# KOS

KOS is a local workflow and state management system for AI-assisted software development. A central Rails API owns the SQLite state for multiple Git repositories, while agents interact with that state only through the `kos` CLI.

## Requirements

- [mise](https://mise.jdx.dev/) with project configuration trusted
- Git and SQLite

Ruby, the Rails bootstrap executable, and Lefthook are pinned in `mise.toml` and `mise.lock`. Application gems and Bundler are locked in `Gemfile.lock`.

## Setup

```sh
mise install
mise run setup
```

`bin/setup` installs gems, prepares the development database, installs Git hooks, and can be safely run again. Local databases and credentials are not committed.

## Development

Start the API on loopback only:

```sh
mise run server
```

By default the development database is `storage/development.sqlite3`. Set `KOS_DATABASE_PATH` to use another central state location. The test environment always uses its isolated test database.

A production process also requires `SECRET_KEY_BASE`; provide both secrets and state paths through the process environment, never committed files. Puma binds to `127.0.0.1` in every environment by default.

## CLI

Set `KOS_API_TOKEN` to the API bearer token. `KOS_API_URL` defaults to `http://127.0.0.1:3000`, and `KOS_API_TIMEOUT_SECONDS` defaults to `30`. Every command is non-interactive and requires `--json`:

```sh
bin/kos task-type list --limit 20 --json
bin/kos workflow get --workflow-version UUID --json
bin/kos task get --repository UUID --task KOS-000123 --json
bin/kos artifact list --repository UUID --task KOS-000123 --limit 20 --json
```

Workflow catalog mutations read only their command body from a JSON file or stdin and require an idempotency key:

```sh
bin/kos workflow-draft import --input draft-import.json --idempotency-key draft-import-1 --json
bin/kos workflow-draft validate --workflow quick-fix --json
bin/kos workflow publish --input publish.json --idempotency-key workflow-publish-1 --json
bin/kos workflow activate --input activate.json --idempotency-key workflow-activate-1 --json
bin/kos workflow export --workflow-version UUID --json
```

The import body contains `workflow_id`, the complete `definition`, and `expected_lock_version`. Publish contains `workflow_id` and `expected_lock_version`; activate contains `task_type`, `workflow_version_id`, and `expected_lock_version`. Use `--input -` to read the body from stdin.

Create a task from an input body containing `title` and `task_type: quick-fix`:

```sh
bin/kos task create --repository UUID --input task.json --idempotency-key task-create-1 --json
```

Claim and maintain workflow-step ownership with the attempt lifecycle commands. Each mutation reads its versioned body from `--input` and requires an idempotency key:

```sh
bin/kos attempt claim --repository UUID --input claim.json --idempotency-key attempt-claim-1 --json
bin/kos attempt renew --repository UUID --input renew.json --idempotency-key attempt-renew-1 --json
bin/kos attempt fail --repository UUID --input failed.json --idempotency-key attempt-fail-1 --json
bin/kos attempt needs-human --repository UUID --input needs-human.json --idempotency-key attempt-human-1 --json
bin/kos attempt reconcile --repository UUID --input reconcile.json --idempotency-key attempt-reconcile-1 --json
bin/kos step context --repository UUID --input context.json --idempotency-key step-context-1 --json
```

Claim requires the task number, owner ID, lease duration, and expected task lock version. Renew, fail, and needs-human require the active attempt ID, fencing token, and expected lock version. Reconcile is available after lease expiry and records the observed recovery state and evidence digest without asserting that an external effect succeeded.

`step context` requires the active attempt ID, fencing token, and expected task lock version. It atomically freezes and returns the pinned instruction, templates, artifact requirements, allowed repository effects, and execution metadata. A status requiring a worktree remains unavailable until its task-bound reservation is confirmed; publication context also remains unavailable until its durable publication intent has been prepared by the publication protocol.

Reserve, confirm, reconcile, and explicitly release task worktrees through the same mutation transport:

```sh
bin/kos worktree reserve --repository UUID --input reserve.json --idempotency-key worktree-reserve-1 --json
bin/kos worktree confirm --repository UUID --input confirm.json --idempotency-key worktree-confirm-1 --json
bin/kos worktree reconcile --repository UUID --input observation.json --idempotency-key worktree-reconcile-1 --json
bin/kos worktree release --repository UUID --input observation.json --idempotency-key worktree-release-1 --json
```

KOS reserves and fences state but does not create or remove a Git worktree. Confirmation and observations must come from the owning orchestrator after `kos-repository` verifies the persisted allocation. Cleanup first records a matching clean worktree as `release_pending`, then records its absence after external removal; dirty or mismatched worktrees remain reserved for explicit resolution.

Prepare, inspect, and reconcile generic repository effects without executing Git through Rails:

```sh
bin/kos effect prepare --repository UUID --input effect.json --idempotency-key effect-prepare-1 --json
bin/kos effect get --repository UUID --effect UUID --json
bin/kos effect reconcile --repository UUID --input result.json --idempotency-key effect-reconcile-1 --json
```

Generic effects cover `commit`, `fetch`, and `rebase`. Preparation binds the request to the active attempt, its frozen context, lease, fencing token, and task lock before an external adapter call. A typed adapter outcome is then recorded as `succeeded`, `failed`, or `unknown`. Prepared and unknown effects survive interruption, transfer to the replacement attempt after recovery, and must be reconciled before that attempt can finish. These commands persist and validate intent only; they never execute Git.

The local repository adapter reads a closed version 1 request from a file or stdin and emits exactly one JSON result. Worktree operations carry the registered repository and reservation snapshots; fetch carries registered trust, durable effect request, and current ownership snapshots:

```sh
bin/kos-repository materialize --input materialize.json --json
bin/kos-repository observe --input observation.json --json
bin/kos-repository remove --input removal.json --json
bin/kos-repository commit --input commit.json --json
bin/kos-repository fetch --input fetch.json --json
```

`materialize` accepts only a `reserved` reservation and creates its exact task branch and path from the expected base commit. `remove` accepts only `release_pending` and never removes a dirty, mismatched, or unproven worktree. `commit` accepts only a matching confirmed reservation and initially clean index, rejects requested paths with configured Git filters, hashes present files with filters disabled, populates an isolated index with explicit blobs, modes, paths, and deletions, verifies the protocol-defined diff and index digests, adds the authoritative `KOS-Task` trailer, and compare-and-swap advances only the reserved branch to the verified explicit tree. Concurrent unrelated index entries cannot enter the commit and are preserved when possible during best-effort real-index refresh after success. An occupied index lock is never removed or overwritten, commit success remains definitive, and worktree files are never reset.

`fetch` embeds the complete durable workflow fetch request and verifies its canonical SHA-256 digest before deriving the exact registered remote and base ref. It proves repository identity before creating the common-directory lock, then repeats complete validation under that lock. Trusted URLs use only `https`, `ssh`, `git`, or `file`, contain no password, query, fragment, or encoded userinfo separator, and may contain a plain SSH username; a `file` URL requires an absolute nonempty path and may contain a host. Fetch rejects remote URL ambiguity, configured bundle URIs, configured URL redirection, HTTP proxy/address overrides, promisor or partial-clone authority, and repository executable transport, proxy, SSH-command, or upload-pack overrides; explicitly resets credential helpers, disables HTTP redirects, and refuses server promisors; disables configured refmaps, tags, pruning, submodules, shallow updates, commit-graph writes, and automatic maintenance; and supplies no destination ref. A successful fetch adds only required objects, changes no refs, index, or worktree, and returns the unique requested-branch commit object observed locally through bounded `FETCH_HEAD` with canonical evidence. It does not claim that every object reachable from that commit is locally complete. Current owner and fencing values are typed and evidence-bound snapshots supplied by the orchestrator; the local adapter does not query Rails to independently establish their freshness. The complete machine documents are defined by `schemas/repository/v1/adapter.json`; Rails effects, runtime skills, and orchestration are separate integration boundaries.

The CLI writes one versioned JSON result to stdout and diagnostics to stderr.

## Checks

```sh
mise run test
mise run lint
mise run security
mise run zeitwerk
mise run check
```

See `AGENTS.md`, `docs/specs/`, `docs/rules/`, and `docs/decisions/` before changing application behavior or architecture.
