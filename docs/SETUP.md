# Local setup

Use **Jac 0.34.19**, matching the exact pin in `jac.toml`. The application source is `/Users/praneeshsurendran/Documents/symphony`.

## Install the application toolchain

Download the official installer, inspect it, and install the pinned release:

```sh
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh -o /tmp/jac-install.sh
bash /tmp/jac-install.sh --version 0.34.19
export PATH="$HOME/.local/bin:$PATH"
jac --version
```

The installer places the self-contained Jac runtime in `~/.local/bin`. Confirm that `jac --version` reports `0.34.19` before running this project.

## Install and verify the project

```sh
cd /Users/praneeshsurendran/Documents/symphony
jac install
jac check main.jac
jac check . --nowarn
jac test tests/dashboard_integration_tests.jac dashboard/models/view_models.cl.jac
jac build --client web
```

Jac 0.34.19 does not support `jac install --frozen`. Keep the team's committed `jac.lock` and npm lock digest unchanged; this migration does not regenerate dependency resolution. Do not regenerate dependency resolution solely to change the compiler version. If exact npm alignment is needed, obtain the matching `.jac/client/bun.lock` from a teammate. Generated environments, dependencies, and bundles stay ignored.

The dashboard retains its atomic architecture under `dashboard/atoms`, `dashboard/molecules`, `dashboard/organisms`, and `dashboard/pages`; presentation models live under `dashboard/models`. Components must explicitly `return` their JSX, including the fixture preview entry point.

## Start development

Preserve an existing `.env`. If it is absent, copy `.env.example` and configure credentials only when enabling live providers.

```sh
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
jac start --dev main.jac
```

Open [localhost:8000](http://localhost:8000). Use the addresses printed by Jac for the frontend and API. Stop the server with Ctrl+C. Do not commit `.env` or provider credentials.

## Fixture verification

Stop the main server before starting the separately labeled preview:

```sh
jac start --dev --port 8010 dashboard_preview.jac
```

Open [localhost:8010](http://localhost:8010). Preview providers are test doubles with no live model or OSV calls. Restart `main.jac` afterward to restore the normal entry point.

## JacHammer

JacHammer is a separate hosting CLI. This machine previously used a compatibility launcher backed by Jac 0.36.1; changing the application's runtime does not change that launcher. Verify the installed CLI with `jachammer --version` before a separately authorized deployment. Local compiler checks do not establish hosting compatibility, provider access, or deployment success.

## Feature scope

The initial dashboard contains six services and five documented dependencies. Feature exports from Members 1 and 2 must be bound in `integration/bindings.jac` to enable live simulation, scanning, investigation, impact, and recovery. Unbound features report unavailable status. See [integration handoff](DASHBOARD_INTEGRATION.md).
