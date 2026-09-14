---
name: kos-initialize
description: Use to inspect and explicitly approve registration and OpenCode runtime installation for one Git worktree.
---

# KOS Initialize

Initialize only the current non-bare Git worktree with the installed non-interactive `kos-initialize` executable. Do not call the KOS API, inspect SQLite, edit a generated plan, or install files manually.

## Required Inputs

Obtain all of these values explicitly from the user:

- an uppercase repository task prefix;
- the configured trusted remote name;
- the complete local base ref in `refs/heads/<name>` form;
- runtime target `opencode` and exact version `1.18.26`;
- one stable registration idempotency key.

Never infer, normalize, or silently confirm the prefix or base ref. Runtime target and version have no alternatives in this release.

## Plan And Approval

1. From the intended repository directory, invoke `kos-initialize plan --input <path|-> --json` with one closed version 1 request.
2. Require one closed successful JSON result. Display the exact canonical Git common directory, worktree root, normalized credential-free trusted remote URL, full base ref, runtime target and version, every managed path and action, drift details, and `plan_digest`.
3. Explain that `conflict` means an existing path is not owned by a valid manifest, even when its bytes match the canonical source. Never describe such a path as adopted.
4. Ask the user to approve that exact digest and whether every listed overwrite is authorized. Do not treat earlier general approval, a suggested ref, or unchanged-looking bytes as approval.

## Apply

After explicit approval, rerun from the same repository with the identical request:

```text
kos-initialize apply --input <path|-> --approved-plan <sha256:digest> --json [--force]
```

Use `--force` whenever the approved plan contains any `update` or `conflict`, including a missing or drifted managed file. Apply rebuilds the complete plan under its installation lock and rejects any digest or destination-observation change before registration or publication. It verifies the installed `kos`, `kos-repository`, active readable published `quick-fix`, OpenCode `1.18.26`, and the complete executable adapter contract against the staged runtime bundle before publishing ordinary copied files. The manifest is published last.

Stop on a malformed result, conflict without explicit force, drift, unsafe object, changed plan, readiness failure, registration failure, capability failure, or partial rollback report. Generate and obtain approval for a new plan after any interrupted or partial installation.

## Boundaries

- Preserve unrelated `.opencode` content. Never delete or rewrite a path outside the managed inventory.
- Never accept symlinks, non-regular managed objects, path traversal, unsafe ancestry, or a malformed or unsupported manifest.
- Installed files are derived copies. Canonical skills remain under the KOS `skills/` source tree.
- Initialization installs `kos-retrospective` instructions but does not provide or claim graceful-end invocation, private-dialogue extraction, timeout enforcement, or separate result delivery.
