---
name: kos-brief
description: Use when the user invokes /kos-brief to specify product behavior, publish specs, and atomically create the reviewed development task graph.
---

# KOS Brief Orchestrator

Act as the user-facing orchestrator for one built-in brief task. Load `kos` for
its runtime-input, safe-path, ownership, human-answer, artifact-verification,
report-recovery, and Git-publication contracts. This skill replaces `kos` only
where it explicitly defines brief creation, the main-agent `brief` step, graph
review and validation, or post-publication materialization. Never access the
KOS REST API, SQLite, or Rails models directly. Use only the exact configured
KOS CLI for KOS state and `okf` for product specifications.

## Accept The Request

`/kos-brief` requires one nonblank valid-UTF-8 product request and uses only the
stable built-in key `brief`. Preserve its exact argument bytes. Canonicalize its
task definition as follows:

- split on LF, remove one trailing CR from each line only for title selection,
  and choose the first line containing a byte other than ASCII space or tab;
- trim only leading and trailing ASCII spaces and tabs from that line, take its
  first 120 Unicode scalar values, and prefix it with `Brief: `;
- set the description to `# Request`, two LF bytes, the exact request bytes,
  and one LF only when the request does not already end in LF.

Do not normalize Unicode, rewrite internal whitespace, or add inferred
requirements to the task description. The request digest is the lowercase
hexadecimal SHA-256 of the exact argument bytes.

Before any KOS mutation, validate the complete runtime contract from `kos`,
including `task resumable`, `create-and-claim`, `show-owned`, `show`, `resume`,
`report-attempt`, `validate-children`, `materialize-children`, and `children`.
The graph commands must expose exactly the documented definition-file, owner,
claim-version, and expected-digest inputs. Missing or incompatible help is
`blocked` before mutation.

## Create Or Resume Exactly Once

Apply the complete durable command-intent, receipt, and lock-directory protocol
from the `kos` skill's `/kos-fix` path with only these substitutions:

- use command kind and task type key `brief` instead of `fix`;
- use `brief-<request-digest>.json`, `brief-<request-digest>-task.json`, and
  `brief-<request-digest>.lock/` beneath
  `<kos-data-home>/intents/<project-id>/`;
- store the exact canonical brief title and description above;
- require a newly claimed brief to have claim version one and first step
  `brief`, with its snapshotted built-in brief workflow.

This includes non-replacing atomic intent and receipt publication, fsync of
files and parent directories, refusal of symlinks, holder token and directory
identity checks, explicit user confirmation before stale-lock recovery,
owner-idempotent `create-and-claim`, and `show-owned` observation after every
ambiguous response. Never create a second task for a surviving matching intent
or receipt.

Unlike the fix path, a matching receipt for a completed brief is a permanent
idempotency binding for that exact request. Inspect the completed task, observed
child graph, and remote publication, then report its existing result; never
delete the receipt or create another brief because a completion response may
have been lost before restart. A matching cancelled brief may be removed only
after the user explicitly chooses to retry that exact request. Contradictory
terminal state is `blocked`.

Before starting a new request, list resumable tasks with `--task-type-key
brief`. A matching receipt identifies its exact task first. Otherwise present
resumable brief titles, statuses, and steps and let the user resume one or start
the new request; never silently replace either choice. Resume and preserve
human answers exactly as `kos` specifies. A material question and its answer
use the current `<step-id>-answer.md` sidecar and survive another interruption.

## Resolve Brief Files

Use `kos` safe-path rules and derive these files beneath the exact task artifact
directory:

```text
brief.md
brief-graph.json
brief-graph-reviewed.json
brief-spec-reviewed.json
brief-graph-validation.json
review.md
publish.md
```

`brief-graph.json` is the current proposal. It is a UTF-8 JSON object with
exactly one top-level key, `children`, containing a nonempty array. Every child
contains exactly `key`, `title`, `description_markdown`, and `blocker_keys`.
Keys are unique nonempty local identifiers; blocker keys name children in the
same proposal and form an acyclic graph.

Every child must be independently executable. Its Markdown description states
the scope, explicit acceptance criteria, and a repository-relative link to each
relevant concept under `specs/`. Prefer one child. Add another only when it has
a genuinely independent result or sequencing boundary, and include only the
minimal dependencies needed for safe execution.

Create and replace graph files atomically through unique regular temporary
files in the artifact directory, exact-byte verification, same-filesystem
rename, and directory fsync. Refuse symlinks, non-regular files, duplicate
candidate files, malformed JSON, or unknown fields. Do not put owner IDs,
claims, secrets, or Git state in a graph file.

## Run Brief In The Main Agent

Before every attempt, verify the current claim and worktree exactly as `kos`
requires. Unlike ordinary steps, exact step ID `brief` must run in this main
conversational agent. Do not delegate it to `kos-step` or another subagent.
Record HEAD and complete status before and after the attempt; HEAD must not
change. Only changes under `specs/` are allowed for a successful brief attempt.

Use `okf` to inspect and update the supplied worktree's product specification.
Resolve enough of the following to define observable behavior without inventing
a material product decision:

- goal, actors, current behavior, and desired behavior;
- rules, errors, edge cases, and failure handling;
- security and privacy implications;
- compatibility and migration requirements;
- observability needed to operate the behavior;
- explicit non-goals and user-visible acceptance criteria.

Ask one precise question only when different answers materially change product
behavior, safety, compatibility, migration, or the development graph. In that
case write the new `brief.md` with the question and return `needs_human`;
do not produce a speculative specification or graph. Clear requirements do not
require an approval pause.

For `specified`, update the conformant `specs/` bundle, atomically write the
complete `brief-graph.json`, then write the new `brief.md` from the supplied
artifact template. The artifact summarizes the specification and graph and
names the exact graph path. Verify both files and the allowed worktree diff
before reporting. Retain the exact graph bytes in session context.

## Review The Specification And Graph

At exact step ID `review`, require the advanced `kos-review` profile and a fresh
agent different from this main agent. Before dispatch, atomically copy the exact
verified `brief-graph.json` bytes to `brief-graph-reviewed.json`; this is the
candidate presented for review, not a normalized or regenerated equivalent.
Also build a deterministic full-tree manifest of `specs/` and atomically store
its exact bytes as `brief-spec-reviewed.json`. Enumerate every path below
`specs/` in ascending raw UTF-8 byte order without following symlinks. Require
regular files and encode canonical JSON with no insignificant whitespace as one
top-level `files` array; each entry contains exactly the repository-relative
path and standard padded Base64 of the file's exact bytes. Construct every
ordered entry as `{"path": path, "content_base64": Base64.strict_encode64(bytes)}`
with `path` inserted before `content_base64`, then serialize the ordered
top-level `{"files": entries}` with Ruby `JSON.generate`. Use Ruby's exact JSON
string escaping and emit no trailing LF. Never hand-build or pretty-print this
authority file. Reject duplicate, non-UTF-8, absolute, `.` or `..` path
components. This includes tracked,
staged, untracked, newly created, and binary specification files without
changing the Git index. Record the graph and manifest identities and bytes
before dispatch. A manifest identical to the base commit's `specs/` tree is a
technical blocker because a brief must publish product behavior.
Supply the reviewer with:

- the complete current `specs/` diff and relevant surrounding concepts;
- the exact `brief-spec-reviewed.json` bytes;
- the exact `brief.md` bytes;
- the exact `brief-graph-reviewed.json` bytes;
- the task request, review instruction, template, and allowed outcomes.

The reviewer remains read-only for the worktree and graph files and writes only
`review.md`. It checks user-facing completeness, OKF validity, graph minimality,
standalone scopes and acceptance criteria, concept links, dependency necessity,
and acyclicity. Approval is allowed only with no actionable finding.
`changes_requested` returns to `brief`; do not preserve the reviewed snapshot as
approval after that transition. Verify unchanged HEAD, status, and graph file
identities around review. Regenerate the canonical full-tree manifest after
review and require byte-for-byte equality with `brief-spec-reviewed.json`, plus
the normal review artifact contract, before reporting its outcome. The
same-path status remaining unchanged is not proof that specification content is
unchanged.

## Validate Before Publication

At exact step ID `publish`, first observe `task children`, local Git, and the
remote default branch. A verified durable validation receipt plus an already
published task commit enters recovery before comparing the current worktree
diff: with no children, continue directly to one materialization attempt; with
an exact complete graph, continue directly to completion reporting. Do not
republish or require the now-clean worktree to reproduce the pre-publication
manifest. An ambiguous publication state or children without verified publication
is `blocked`. Only a task with no children and no published task commit follows
the initial path below.

For that initial path, first read `brief-graph.json` and
`brief-graph-reviewed.json` without following symlinks. Require their bytes to
be identical to each other. When authoritative task state is `publish`, a
restart may reconstruct the approved-review bytes from the safe durable graph
and specification snapshots; no in-memory value from the prior process is
required. Regenerate the current canonical `specs/` full-tree manifest and
require exact equality with `brief-spec-reviewed.json` and those reconstructed
approved bytes.
If any graph or specification byte differs, do not invoke
`materialize-children` and do not publish;
return to `brief` through `graph_invalid` with a truthful atomic `publish.md`.

Invoke `<kos-cli> task validate-children <task-id> --definition-file
<brief-graph-reviewed.json>` using distinct process arguments. Require a
complete success response whose parent is this brief, whose canonical digest
has the `sha256:` form, and whose returned canonical children correspond to the
submitted graph. Retain both the exact reviewed bytes and returned digest. An
invalid graph reports `graph_invalid`, which repeats `brief` and independent
review. A transport failure is ambiguous only with respect to validation, which
has no mutation; retry it at most once after re-verifying the exact bytes.

After successful validation and before publication, atomically write
`brief-graph-validation.json` containing exactly the returned canonical digest,
the lowercase SHA-256 of the exact reviewed graph bytes, and the lowercase
SHA-256 of the exact reviewed specification manifest bytes. Fsync it and its
directory. On restart, accept this receipt only when every field is well formed,
both current reviewed files hash to its values, and the workflow is still at
`publish`; otherwise repeat validation when no children exist or stop blocked.

For an initial publication, the observed child result must contain no children
and a null digest. Any partial or contradictory graph is `blocked`.
Never materialize children before publication is observed remotely.

## Publish Then Materialize

After successful validation, launch one fresh standard `kos-publish` agent.
Supply the exact brief publication context required by `kos` and `kos-git`, and
explicitly supply the exact `brief-spec-reviewed.json` bytes and limit the
publishable task diff to reviewed `specs/` changes. Immediately before staging,
the publisher must regenerate the canonical full-tree manifest and require
byte-for-byte equality. It must stage only that `specs/` change and require the
candidate commit's complete `specs/` tree to reproduce the manifest exactly
before push. A mismatch is a technical stop without commit or push. The
publisher may commit and push the bound change and write the new `publish.md`;
it must never call a KOS graph command. Handle `base_moved` through the workflow
outcome so `brief`, review, and validation all repeat on the new base.

When the publisher returns `published`, first verify remote publication through
the `kos-git` protocol. Then re-read both graph files and require exact equality
with the retained reviewed bytes. A byte mismatch after push is a technical
`blocked` condition: do not call materialization, do not change the reviewed
graph, and do not use `graph_invalid` for an already published specification.

Only after those checks invoke:

```text
<kos-cli> task materialize-children <task-id> \
  --definition-file <brief-graph-reviewed.json> \
  --owner-id <owner-id> \
  --claim-version <claim-version> \
  --expected-digest <validated-digest>
```

Pass every value as a distinct process argument. Require the returned digest to
equal the retained digest and the complete children to match the reviewed graph.
Do not report `published` yet.

## Recover Materialization

Every incomplete, malformed, failed, or contradictory materialization response
is ambiguous. Never blindly repeat it. Invoke `task children <task-id>` and
compare the complete observed child graph and digest with the retained reviewed
bytes and validated digest. After a process restart, recover those values only
from the verified `brief-graph-reviewed.json`, `brief-spec-reviewed.json`, and
`brief-graph-validation.json` files.

- An exact complete match proves materialization succeeded once.
- No children and a null digest prove no mutation occurred; after re-verifying
  the claim, reviewed bytes, and digest, one identical retry is safe.
- A partial graph, different digest, changed definition, stale ownership, or
  unavailable observation is `blocked` without changing any child or graph.

When a resumed publish step already has an exact complete child graph, use
`kos-git` to observe the task commit and remote default branch before doing
anything else. Exact remote publication plus graph and validation-receipt
agreement proves both side effects completed; proceed directly to reporting
`published` without validating, publishing, or materializing again. If remote
publication is absent or ambiguous, stop `blocked`; children must never be
silently accepted as evidence of a push.

For every published-state recovery, require the observed remote task commit's
complete `specs/` tree to reproduce `brief-spec-reviewed.json` exactly. If the
publisher crashed after push but before writing `publish.md`, this main
orchestrator writes that new artifact from the observed commit, remote,
validation receipt, and child graph facts before reporting. It never invents
success from a local candidate alone.

If post-publication materialization or observation is blocked, write the new
`publish.md` with the precise published Git state and technical graph
cause before reporting the allowed `blocked` outcome. This main orchestrator is
the authority for that post-publisher observation artifact; it may not alter
the worktree or published commit.

## Complete Only After Observation

Only after exact materialization is observed may the main orchestrator report
the publish step's `published` outcome. Verify `publish.md` first and use the
normal lost-report protocol from `kos`. If completion response is lost, `task
show` proving completed status, released ownership, and exactly one claim
increment is success; never repeat materialization or create another commit.

Children must remain pending and blocked by this active brief between
materialization and accepted completion. After completion, observe the complete
child graph once more. Report success only when the graph still matches and
only children whose sibling blockers are complete are available.

Continue autonomously until completed, one material question needs the user, or
a concrete technical blocker prevents safe progress. Never implement a child
development task in the brief session and never claim success before remote
publication, graph materialization, and parent completion are all observed.
