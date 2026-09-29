---
name: kos-setup
description: Use when installing or checking the KOS server, kos CLI, and OpenCode integration from the KOS repository.
---

# Set up KOS with OpenCode

Follow the repository's README "Server Setup", "CLI Installation", and "OpenCode Integration" sections. Start the Rails server on loopback, build and install the CLI gem, then run `ruby script/install-opencode` from the KOS checkout. The installer only adds KOS-owned global skills and agents; it stops if an existing target differs.

Restart OpenCode after installation. Check `kos` is on PATH, `opencode models openai` lists `openai/gpt-6-luna` and `openai/gpt-6-sol`, and `opencode agent list` shows `kos-standard` and `kos-advanced`. In the target Git repository, load the `kos-orchestrator` skill from the current main agent when working on a KOS task, or specify `KOS_PROJECT` explicitly. Choose a stable and unique `KOS_SESSION_ID` for this OpenCode session before claiming work. If setup fails, report the failed check without changing existing user configuration.
