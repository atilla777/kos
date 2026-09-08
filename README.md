# KOS

KOS is a local workflow and state management system for AI-assisted software development. A central Rails API owns the SQLite state for multiple Git repositories, while agents interact with that state only through the `kos` CLI.

## Requirements

- [mise](https://mise.jdx.dev/) with project configuration trusted
- Git and SQLite

Ruby, the Rails bootstrap executable, and Lefthook are pinned in `mise.toml` and `mise.lock`. Application gems and Bundler are locked in `Gemfile.lock`.

## Setup

```sh
mise install
mise run setup
```

`bin/setup` installs gems, prepares the development database, installs Git hooks, and can be safely run again. Local databases and credentials are not committed.

## Development

Start the API on loopback only:

```sh
mise run server
```

By default the development database is `storage/development.sqlite3`. Set `KOS_DATABASE_PATH` to use another central state location. The test environment always uses its isolated test database.

A production process also requires `SECRET_KEY_BASE`; provide both secrets and state paths through the process environment, never committed files. Puma binds to `127.0.0.1` in every environment by default.

## Checks

```sh
mise run test
mise run lint
mise run security
mise run zeitwerk
mise run check
```

See `AGENTS.md`, `docs/rules/`, and `docs/decisions/` before changing application behavior or architecture.
