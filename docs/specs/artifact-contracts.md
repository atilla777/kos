---
title: KOS Artifact Contracts
status: active
---

# KOS Artifact Contracts

## Artifact Model

A `TaskArtifact` is an immutable, registered workflow result, such as a document, ADR, candidate commit, test result, review result, or publication. It records an identifier, type, attempt ID, producer, state, and the type-specific repository path, commit, subject, content digest, external reference, or evidence metadata required to validate that artifact. A generic evidence digest is not required when the typed fields already identify the evidence completely.

Correcting evidence creates a new artifact; an approved artifact is not edited. A permanent task artifact is created only when its workflow requires one. Artifact payloads are not workflow-catalog content: task documents, when required, live under `tasks/<task-number>/`, and Git evidence may refer directly to a commit without a Markdown file. KOS stores their immutable registration metadata so transition validation remains transactional.

A `PublicationResult` is not a `TaskArtifact` and does not satisfy a workflow transition. It is the immutable pre-cleanup handoff of the exact succeeded publication child manifest and the verified snapshot that binds its original producer and input context to the reviewed candidate, passed checks, trusted target, and canonical reachable push evidence. A replacement attempt may retrieve that record and authorize cleanup but cannot register it as transition evidence or change its producer, context, manifest, or evidence.

## Transition Validation

For each workflow status, the pinned schema defines required artifacts by type, cardinality (`one` or `many`), subject (`task` or `candidate`), and allowed states. Entering review, for example, requires one produced task candidate and one or more passed test results for that candidate. Moving from review to publication requires one `approved` review result for the exact candidate.

The CLI validates the universal structural contract:

- required artifacts exist and have allowed states;
- artifacts belong to the task and relevant attempt;
- subject candidate SHA and version relationships are consistent; and
- the requested workflow transition is allowed.

For document evidence it validates repository-relative path, commit SHA, and blob or content digest. For a candidate it validates commit existence, repository identity, and the task trailer. Planning and development additionally require exactly one successful commit effect from that attempt, the same reservation as its frozen context, and a latest clean observed HEAD equal to both the effect's returned commit and the document or candidate SHA before transition. Base synchronization instead requires exactly one owner-bound successful trusted fetch followed by one successful rebase of the frozen reservation and HEAD onto that fetched OID; one transaction records rebase success and a canonical clean worktree observation, and the result must equal the durable reservation HEAD while differing from the superseded candidate generation. A replacement attempt after post-reconciliation interruption may satisfy this with its own verified no-op rebase at that already changed HEAD. For a test result it validates candidate SHA, command, exit code, and log digest. For review it validates candidate SHA, verdict, a distinct review attempt, no review-owned repository effect, and a post-context-capture clean worktree observation canonically bound to that attempt's fencing token, frozen input-context digest, and the same candidate as the frozen context and current generation. For publication it validates trusted remote and ref evidence obtained by fetch. An earlier `PublicationResult` preserves the future publication artifact's exact child manifest and verified evidence across cleanup recovery, but artifact registration and terminal transition remain a distinct operation. The CLI does not assess whether requirements, implementation, or review are substantively good.

The generic `kos-workflow-step` executor follows the pinned state instruction, verifies its work, and returns a result manifest. The lease-owning orchestrator submits that manifest to one CLI command, which validates the lease, expected lock version, dependencies, artifact contract, and transition, then registers artifacts and changes workflow status in one SQLite transaction.

A review attempt cannot be the development attempt. Evidence produced by the same attempt is a `self-check`, not an approved independent review.

## Artifact Generations

Candidate-specific test, review, and publication artifacts form one generation keyed by candidate SHA. If a new candidate is created, evidence for the prior SHA does not satisfy the new generation's contract.

Typical required evidence includes:

| Workflow activity | Evidence |
| --- | --- |
| Requirements | A valid OKF document when required by the workflow |
| Architecture decision | An ADR when required by the selected branch |
| Development | Test result and candidate commit SHA before review |
| Review | An `approved` result for the candidate SHA from a separate attempt |
| Publication | Fetch-based proof that the same SHA is reachable from the configured remote base ref |

Detailed artifact and result-manifest JSON schemas and exact error response shapes are defined by [CLI Protocol Version 1](cli-protocol.md).
