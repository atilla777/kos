---
title: KOS Artifact Contracts
status: active
---

# KOS Artifact Contracts

## Artifact Model

A `TaskArtifact` is an immutable, registered workflow result, such as a document, ADR, candidate commit, test result, review result, or publication. It records an identifier, type, attempt ID, producer, subject SHA or content digest, repository-relative path or external reference, state, evidence digest, and type-specific metadata such as a test command or review verdict.

Correcting evidence creates a new artifact; an approved artifact is not edited. A permanent task artifact is created only when its workflow requires one. Task documents, when required, live under `tasks/<task-number>/`; Git evidence may refer directly to a commit without a Markdown file.

## Transition Validation

For each workflow status, the pinned schema defines required artifacts by type, cardinality (`one` or `many`), subject (`task` or `candidate`), and allowed states. Entering review, for example, requires one produced task candidate and one or more passed test results for that candidate. Moving from review to publication requires one `approved` review result for the exact candidate.

The CLI validates the universal structural contract:

- required artifacts exist and have allowed states;
- artifacts belong to the task and relevant attempt;
- subject candidate SHA and version relationships are consistent; and
- the requested workflow transition is allowed.

For document evidence it validates repository-relative path, commit SHA, and blob or content digest. For a candidate it validates commit existence, repository identity, and the task trailer. For a test result it validates candidate SHA, command, exit code, and log digest. For review it validates candidate SHA, verdict, and a distinct review attempt. For publication it validates trusted remote and ref evidence obtained by fetch. The CLI does not assess whether requirements, implementation, or review are substantively good.

The producing capability skill verifies its work and returns a result manifest. For example, `kos-development` chooses and runs project-required tests, while `kos-review` applies review criteria. The lease-owning orchestrator submits that manifest to one CLI command, which validates the lease, expected lock version, dependencies, artifact contract, and transition, then registers artifacts and changes workflow status in one SQLite transaction.

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
