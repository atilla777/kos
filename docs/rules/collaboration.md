---
title: KOS Development Collaboration Rules
status: active
---

# KOS Development Collaboration Rules

## Sources Of Truth

- Keep product requirements, behavioral specifications, engineering rules, and architecture decisions in this Git repository. Use `docs/specs/` for observable contracts, `docs/rules/` for engineering constraints, and `docs/decisions/` for accepted architecture decisions.
- Keep the development roadmap, task list, task status, blockers, risks, and next action outside the repository in `/home/aleksei/Yandex.Disk/obsidian-vault/B - работа Plums Lab/Klad/KOS/KOS - план реализации.md`.
- Read the external plan before discussing a new development task. If the path is unavailable, ask the user for its current location and do not start the task until the plan has been read.
- Do not duplicate the roadmap or operational task status in the repository. Do not keep normative product specifications only in Obsidian.
- Treat `README.md` as user-facing product documentation. Do not use it for the roadmap, MVP boundaries, internal development plans, or agent rules.
- Do not silently resolve a conflict among the plan, specifications, rules, ADRs, and code. Show the conflict to the user and wait for a decision.

## Task Scope

- Keep each task limited to one cohesive, independently verifiable result. Its requirements, diff, and checks must be reviewable as one unit.
- Propose decomposition before implementation when a request contains independently useful outcomes, crosses unrelated domains, or requires too many decisions for one reviewable change.
- Do not include unrelated refactoring, cleanup, or opportunistic improvements. Record them as proposed follow-up tasks instead.
- Apply this process proportionally. Discussion for an obvious small change may be brief, but requirements, a plan, and explicit implementation approval remain mandatory.

## Session Boundary

- Work on at most one task in a session. Discussion, approval, implementation, verification, and publication of that task may happen in the same session.
- After completing or blocking the task, report and record the next task but do not start it in the current session.
- A task that cannot be finished in one session may continue in a new session. Reconstruct its state from Git, repository documentation, and the external plan rather than relying on conversation history.

## Discovery And Discussion

- Hear the user's vision, goals, and expected behavior before choosing a solution. Read relevant code and documentation without modifying them so the discussion reflects the current system.
- Resolve material uncertainty before implementation. Ask about behavior, scope, data, compatibility, security, architecture, acceptance criteria, and other decisions that cannot be established from the repository.
- Group related questions into small, understandable sets. Do not ask the user for facts that can be reliably discovered in the project.
- When a material decision has alternatives, number the options, state their relevant consequences, advantages, and disadvantages, and identify the recommended option. Ask the user to choose by entering the corresponding number.
- Do not invent a product decision because discussion would delay implementation.

## Agreed Baseline And Approval

- At the end of discussion, present a self-contained summary in clear language. Include enough context to understand the change without reconstructing it from earlier messages.
- The summary must cover the goal and user-visible result, current context, requirements, scope, non-goals, accepted decisions, acceptance criteria, implementation plan, verification plan, known risks, and unresolved questions.
- Do not modify code, documentation, configuration, Git state, project state, or external systems before the user explicitly approves both the final requirements and the implementation plan, then separately authorizes implementation.
- Approval of requirements or discussion completion alone is not authorization to implement. Treat an ambiguous response as no authorization.
- After authorization, mark the selected task `in-progress` in the external plan before implementing it.

## Implementation Control

- Implement only the approved scope. Make routine local implementation decisions independently only when they do not change behavior, architecture, risk, dependencies, or task size.
- Once implementation is authorized, continue without further prompting through implementation, required verification, documentation and plan updates, commit, and publication. Resolve technical issues independently when they stay within the agreed baseline.
- Do not stop merely to report progress or ask the user to perform work that the agent can safely perform. Stop only when a user decision is required, the agreed baseline must materially change, data or unrelated work may be at risk, required checks cannot be made to pass within scope, concurrent changes directly conflict with the task, or credentials, connectivity, or repository policy prevent publication.
- Stop implementation if new information requires changing requirements, architecture, an external contract, the data model, dependencies, or the approved scope in a material way.
- Explain why the baseline must change, provide numbered alternatives when appropriate, and continue only after the user chooses and explicitly authorizes the revised plan.
- Preserve unrelated worktree changes and never use them as a reason to broaden the task.

## Publication

- Implementation authorization includes permission to commit the completed task and publish it with a normal push to the repository's default branch after all required checks pass, unless the user explicitly restricts publication for that task.
- Commit only files that belong to the approved task. Never force-push, bypass branch protection or hooks, discard unrelated work, or publish known failing changes.
- If publication fails, preserve the verified local work, mark the task `blocked`, record the exact blocker and next action in the external plan, and report what the user must do.

## Completion

- On completion or blockage, update the external plan with the task status, result, risks, blockers, and next action.
- Give a brief, clear final report stating what was done; what changed for a KOS user, or explicitly that user-visible behavior did not change; which checks ran; the commit, branch, and push result; the next task; and what the user must do, explicitly stating when no action is required.
- Include any unverified behavior, remaining risk, blocker, or proposed follow-up needed to interpret the result safely.
- Do not mark a task complete until its approved acceptance criteria and required verification are satisfied.
