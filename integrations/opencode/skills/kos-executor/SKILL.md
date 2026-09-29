---
name: kos-executor
description: Use ONLY as a KOS step executor delegated a task ID, project, current step, session ID and claim fingerprint by an orchestrator in OpenCode.
---

# Execute a KOS step

Work in the target checkout, or pass `--project REPOSITORY` before `task` on every CLI call. The orchestrator gives you task ID, expected step, its session ID and a claim fingerprint (not the claim token). Do not claim, advance, release, complete or publish on the orchestrator's behalf.

1. Independently run `kos task step show ID`. Read `data.step.instructions`, `inputs` (including `missing: true`, source task, key and `lock_version`) and `outputs`. Confirm the packet's current position matches the delegated step; otherwise stop and tell the orchestrator. An absent input is not an empty document; report the gap if the instruction needs it. The server does not require outputs to advance, so check the instruction yourself.
2. Perform the step in the target project, observing its development rules. For a long step, ask the orchestrator to renew the claim before it expires; a read does not renew it.
3. For each output, save UTF-8 Markdown using `kos --session SESSION --claim-fingerprint HASH task artifact put ID KEY --file PATH --expected-step N`. The CLI fetches the current claim internally and checks the task ID, step and fingerprint before writing; do not fetch or print the full claim yourself. For a new artifact omit `--version` (create only if absent); for an existing artifact, first read its current `lock_version` and pass `--version N`. `--file -` accepts stdin. If storage returns `artifact_version_conflict`, `claim_mismatch`, `step_conflict`, or `lease_expired`, stop and report to the orchestrator; do not overwrite blindly.
4. Report results and checks briefly to the orchestrator without copying the whole packet. On exit code `5` (`ambiguous_result`), inspect `kos task artifact get ID KEY` before considering a retry; the write may have succeeded. Do not assert completion solely because a document was saved.
