---
name: kos-setup
description: Use when installing, updating or checking the local KOS server, kos CLI, and OpenCode integration from the KOS repository.
---

# Set up KOS with OpenCode

Follow the repository's README "Server Setup", "CLI Installation", "OpenCode Integration", and "Updating an existing installation" sections as appropriate. On a new installation run `bin/rails db:prepare` then `bin/rails db:seed` to install the shared Brief, Execution and Fix workflow definitions. For an update, inspect the checkout and running service first; fetch from the expected GitHub origin and fast-forward only a clean main. Never discard local commits or changes. Build and install the CLI gem, then run `ruby script/install-opencode` from the KOS checkout. The installer updates only files matching known previous KOS versions; it stops before copying if a destination was modified or is of unknown origin. It also installs the `/kos-init`, `/kos-update`, and `/kos` commands.

Updating files is not consent to migrate the persistent SQLite database or restart the Rails server. Check pending migrations and their effects first. Before requesting separate explicit migration approval, create and verify an online backup as described in README; ask independently for approval to restart the server. After confirming the schema is compatible (and completing an approved migration if needed), run the idempotent seed as part of installation; inspect the three definitions and report any incompatible existing edition rather than overwriting it. If declined, report which components remain on the old version. Do not automatically restore on failure or claim an update succeeded when some components failed.

Ask the user to quit and restart OpenCode after installation to load new commands and skills. Check `kos` is on PATH, `opencode models openai` lists `openai/gpt-6-luna` and `openai/gpt-6-sol`, and `opencode agent list` shows `kos-standard` and `kos-advanced`. In the target Git repository, use `/kos` or load the `kos-orchestrator` skill from the current main agent when working on a KOS task, or specify `KOS_PROJECT` explicitly. Choose a stable and unique `KOS_SESSION_ID` for this OpenCode session before claiming work. If setup fails, report the failed check without changing existing user configuration.
