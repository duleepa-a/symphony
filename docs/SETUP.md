# Local setup

Use **Jac 0.34.19**, matching the exact pin in `jac.toml`. Run all commands from the repository root. On Windows, use WSL (Ubuntu) and open the repo at its `/mnt/<drive>/...` path, for example `cd "/mnt/d/Hackthon/Hackathon AI/symphony"`.

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
cd <repository root>
jac install
jac check main.jac
jac check . --nowarn
JAC_TEST_JOBS=0 jac test tests/feature_integration_tests.jac tests/agent_integration_tests.jac tests/dashboard_integration_tests.jac dashboard/models/view_models.cl.jac investigation/agent.jac investigation/validation.jac simulation/fixtures.jac
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

After changing server validation, diagnostic tools, agent bindings, or provider configuration, stop Jac with Ctrl+C and start it again. Refreshing the browser alone can leave imported server code from the previous process active. Restarting clears the process-local simulation and investigation results; trigger the incident and investigate again.


## Fixture verification

Stop the main server before starting the separately labeled preview:

```sh
jac start --dev --port 8010 dashboard_preview.jac
```

Open [localhost:8010](http://localhost:8010). Preview providers are test doubles with no live model or OSV calls. Restart `main.jac` afterward to restore the normal entry point.

## JacHammer

JacHammer is a separate hosting CLI. This machine previously used a compatibility launcher backed by Jac 0.36.1; changing the application's runtime does not change that launcher. Verify the installed CLI with `jachammer --version` before a separately authorized deployment. Local compiler checks do not establish hosting compatibility, provider access, or deployment success.

## Feature scope

The initial dashboard contains six services and five documented dependencies. Simulation, diagnostics, OSV, Investigator, impact and manual recovery use their real feature exports. The new Security Analyst and Recovery agents await their feature-owner handoff; prerequisite and unavailable errors remain explicit. See [dashboard integration](DASHBOARD_INTEGRATION.md) and [agent integration](AGENT_INTEGRATION.md).
