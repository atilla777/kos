---
description: Set up and check the local KOS server, CLI, and OpenCode integration.
agent: build
---

Set up KOS for this machine using the `kos-setup` skill and the repository README. Ask for the KOS checkout path if it is not known. Inspect the existing installation and database before changing anything. Do not migrate an existing database or restart a running server without separate, explicit permission for each operation. If migration is needed, show its effect, make and verify an SQLite backup before asking for migration permission. For a selected target project, load `kos-project-onboarding` and conservatively create or extend its `AGENTS.md` and mandatory `rules/index.md` after verifying the repository. If no target project is selected, do not modify other projects; explain how to connect one later. Report what is installed and what still needs action. Additional user instructions: $ARGUMENTS
