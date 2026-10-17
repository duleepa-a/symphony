# Local setup

The supplied repository at `/Users/praneeshsurendran/Documents/symphony` is the application source. Use **Jac 0.37.25**, matching the exact pin in `jac.toml`.

## Install the application toolchain

Download the official installer, inspect it, and select the pinned release:

```sh
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jac/v0.37.25/scripts/install.sh -o /tmp/jac-install.sh
bash /tmp/jac-install.sh --version 0.37.25
export PATH="$HOME/.local/bin:$PATH"
jac --version
```

The installer places `jac` in `~/.local/bin`. Keep that directory on your shell PATH. The binary carries its own Python and JavaScript toolchains.

## Install and verify the project

```sh
cd /Users/praneeshsurendran/Documents/symphony
jac install --frozen
jac check main.jac
jac check --nowarn
jac build --as client
```

Use `jac install` when intentionally resolving or updating dependencies; review changes to `jac.lock`. The environment, npm dependencies, compiler caches, and generated client live under ignored directories.

## Start development

If `.env` is absent, copy `.env.example` to `.env`. Preserve an existing file. Replace the example credential only when enabling live investigation; the dashboard and placeholder operations need no provider key.

```sh
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi
jac run --dev --host 127.0.0.1 main.jac
```

Open [localhost:8000](http://localhost:8000). The commands load `.env` when present and bind the API to `127.0.0.1`. Use `jac --version` to confirm the pinned 0.37.25 runtime. Jac 0.37.25 starts a separate Vite frontend in HMR mode and may advertise a LAN URL. Add `--port 8002` before `main.jac` if port 8000 is occupied. Stop it with Ctrl+C.

Secrets must stay in the ignored `.env` or the hosting platform's environment settings. Never put provider keys in client code or committed configuration. Loading `.env` does not verify provider/model availability.

## JacHammer CLI compatibility

The official CLI artifact served by `jachammer.ai` during setup was v0.2.0, build `prod@a98b958`. Its source declares Jac 0.34.0–0.36.1 as its tested runtime range. It fails to compile under the application's Jac 0.37.25 runtime.

Keep the application on **0.37.25**. A separate **0.36.1** runtime can run the hosting CLI without replacing the app's `jac` command. This machine's compatibility launcher uses `~/.jachammer/runtime/jac-0.36.1` for the CLI and preserves the original launcher at `~/.jachammer/lib/jachammer-launcher.original.sh`. The regular PATH still selects the application's 0.37.25 toolchain.

Verify both tools before deployment:

```sh
jac --version
jachammer --version
jachammer login
jachammer link <project-name>
jachammer deploy --dry-run
jachammer deploy
```

Login, project linking, upload, and deployment are separate from local setup. Do not run them merely to verify installation. A CLI update may overwrite the local compatibility launcher; recheck runtime compatibility afterward. The JacHammer web dashboard is an alternative deployment path.

## Foundation scope

The initial state contains six services and five documented dependencies. Simulation, OSV scanning, impact analysis, and recovery remain explicit placeholders. Investigation requires a valid model credential and connected diagnostics. Setup does not implement these features or claim successful scans or model investigations.

## Verified setup — 17 October 2026

- Application runtime: Jac 0.37.25, official download checksum verified.
- Hosting CLI: JacHammer 0.2.0 (`prod@a98b958`), running on its separate checksum-verified Jac 0.36.1 runtime. Verified from this project directory.
- Python and npm dependency installation completed; `jac install --frozen` passed. The team's original npm lock digest was restored after setup. Exact local npm version alignment requires the matching Bun lockfile from a teammate; the locally generated Bun lockfile is different.
- `jac check main.jac` and the full-project `jac check --nowarn` passed.
- `jac build --as client` passed.
- The Jac development server started the dashboard on localhost:8000 and the API on localhost:8001.
- Live dashboard response: six healthy services and exactly five documented dependencies; no hidden dependency present.
- All eight unfinished operation endpoints returned their explicit not-implemented status and expected error code.
- `/healthz/live` and `/healthz/ready` returned HTTP 200.
- Browser rendering and incident/scan placeholder interactions passed with no captured console errors.
- Live model calls, OSV lookups, account login, and hosting deployment were not invoked.

These checks verify the foundation and development environment; they do not mark unfinished product features as implemented.
