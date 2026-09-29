---
description: Safely update the local KOS checkout, CLI and OpenCode integration from GitHub.
agent: build
---

Update KOS using the `kos-setup` skill and the README "Updating an existing installation" section. Ask for the KOS checkout path if unknown. Follow the preflight and fast-forward-only GitHub update instructions. Check installed files before replacement; stop on unknown or locally modified files. Do not migrate the existing database or restart a running server unless the user explicitly approves each operation separately after seeing the plan and migration backup. Explain partial failures and verify what was updated. Tell the user to restart OpenCode to load the new commands and skills; this does not authorize restarting the Rails server. Additional user instructions: $ARGUMENTS
