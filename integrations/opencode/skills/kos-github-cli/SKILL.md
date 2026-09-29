---
name: kos-github-cli
description: Use ONLY for explicit GitHub CLI (gh) operations such as pull requests, GitHub checks, issues, releases or repository queries; not for an ordinary request to edit code.
---

# Work with GitHub through gh

Read the project's `AGENTS.md` and applicable instructions first. Use the installed `gh` CLI for GitHub actions, not guessed HTTP endpoints. If `gh` is missing or authentication or repository access fails, report the failed check and leave local and remote work intact. For an unfamiliar operation or flag, consult `gh help`, `gh help <command>` or `gh <command> --help`; examples do not limit which `gh` operations are available.

For a requested PR, inspect the local branch, `git status`, `git diff`, recent history and remote tracking; review every commit and the diff against the intended base. Check the destination repository and base branch before `gh pr create`, then confirm the PR URL and its resulting state through `gh`. Use `gh pr view` and `gh pr checks` to inspect an existing PR and its checks; a failed or pending check is not a successful publication. Create a PR, merge it, publish a release, or make another remote change only when expressly requested or required by the applicable project instructions for the assigned task. Follow the project's chosen publication route; do not substitute a PR for a required local merge or merge a PR without the required review.

If the branch or base is wrong, a PR already exists, checks fail, `gh` fails, or the remote result is ambiguous, inspect the current state before retrying. Report what succeeded and what remains, without force-pushing, deleting branches or overwriting unrelated work. Use `kos-git` for explicit local Git work when needed.
