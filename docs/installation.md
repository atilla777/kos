# Installation

Install every KOS component from one checked-out Git revision. Do not combine a
server, CLI, or OpenCode integration from different revisions.

## Prerequisites

- Ruby 3.4.10 and Bundler 4.0.20;
- SQLite 3 with development headers;
- Git;
- OpenCode 1.18.26 or later with credentials for the models selected in the
  installed agent profiles.

## Install

Check out the selected release commit or tag, configure the persistent local
data directory and bearer token, then install dependencies and prepare the
database:

```sh
git fetch --tags
git checkout <release-tag-or-commit>
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="$(openssl rand -hex 32)"
bundle check || bundle install
bin/rails db:prepare
```

Build and install the CLI outside the checkout:

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" --version
"$KOS_CLI_PATH" --help
```

Install the commands, agents, and skills from the same checkout:

```sh
bin/install-opencode
```

The default destination is `$XDG_CONFIG_HOME/opencode`, or
`~/.config/opencode`. Use `--config-home <absolute-path>` for an isolated or
nonstandard OpenCode installation. Restart OpenCode after installation because
a running process does not reload commands, agents, or skills.

The installed defaults use `openai/gpt-5.6-terra` with medium reasoning for
standard execution and publication, and `openai/gpt-5.6-sol` with high
reasoning for advanced planning, diagnosis, and review. `/kos` and `/kos-fix`
use Terra for orchestration; `/kos-brief` uses Sol because product clarification
and graph design run in the main conversational agent. Verify availability with
`opencode models openai`. Administrators may substitute complete
`provider/model-id` values while preserving the standard and advanced roles.

## Configure And Start

Start Rails in a dedicated terminal or service process. Configure that process
with the same data directory and token created during installation:

```sh
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
bin/rails server
```

In another terminal, verify readiness and register the project through the
installed CLI. Configure that process with the same token and the absolute CLI
path:

```sh
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
curl --fail "$KOS_API_URL/up"
"$KOS_CLI_PATH" project create \
  --name "My project" \
  --remote-url "$(git remote get-url origin)" \
  --default-branch "$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')"
```

Retain the returned project ID and expose the server, CLI, and exact registered
project values to the OpenCode process:

```sh
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
export KOS_PROJECT_ID="<registered-project-id>"
export KOS_PROJECT_REMOTE_URL="<registered-project-remote-url>"
export KOS_PROJECT_DEFAULT_BRANCH="<registered-default-branch>"
```

Database preparation installs the `brief`, `development`, and `fix` task types
and their canonical workflows. No workflow JSON or numeric task type setting is
required. After restarting OpenCode, verify that `/kos-brief`, `/kos`, and
`/kos-fix` are discoverable before treating the installation as ready.

## Update

Stop the service and active orchestrators, check out one new revision, rebuild
the gem, rerun `bin/install-opencode`, prepare and seed the database, and then
restart Rails and OpenCode:

```sh
bin/rails db:prepare
bin/rails db:seed
```

Bootstrap reuses identical built-in workflows and creates immutable revisions
for changed definitions. Existing tasks keep their snapshotted workflow.
