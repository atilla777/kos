# Project agent instructions

## KOS task tracking

For a request to work on this project through KOS, load `kos-orchestrator`; `/kos` is an optional shortcut. Verify the repository's actual Git `origin` before identifying the project. Use `kos session new` once per new conversation if no session ID is already available; reuse the ID when continuing. Follow this project's development and publication rules, and confirm publication before completing a task.

Read the [development rules](rules/index.md) before planning, changing files, reviewing or publishing. Approved user-facing behavior lives in the OKF v0.2 bundle at {{SPEC_BUNDLE_INDEX}}; code and tests show current behavior. Material changes to required behavior need explicit human agreement. Significant technical decisions may be recorded as OKF ADRs under `docs/adr/`; their current requirements belong in `rules/`.

Use the person's language unless this project specifies another. In ordinary chat ask one question at a time (a sequential wizard may hold several); explain context and offer a recommendation with a short reason in parentheses without inventing factual answers. Keep progress, blockers and final reports plain and understandable.
