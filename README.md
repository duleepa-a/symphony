# SYMPHONY

Agentic Reliability & Security Intelligence

> Uncover hidden dependencies. Investigate failures. Expose vulnerabilities.

SYMPHONY is a Jac 0.34.19 full-stack foundation for investigating a simulated six-service topology. The service inventory is simulated. Production advisory lookups and model investigation become live only when the corresponding feature implementations are integrated.

## Member 3 dashboard

The dashboard now provides:

- Independent incident, investigation, scan, impact, and recovery states, including loading, completed, empty, partial, failed, and unavailable outcomes.
- A selectable six-service graph driven by returned service health and dependencies, with separate documented and trace-backed discovery styles and an accessible relationship list.
- Investigation timeline, observed evidence, ranked candidates, discovered relationships, and explanation.
- Package-level advisory results, external references, unknown severity, and explicit incomplete/error coverage.
- Potential-exposure analysis and a non-destructive recovery comparison.
- Run/request/service guards that reject stale responses after reset, a new incident, or selection changes.
- Keyboard-visible focus, a skip link, live status feedback, reduced-motion support, and a horizontally scrollable graph on narrow screens.

**Integration status:** this branch contains no Member 1 simulation modules or Member 2 scanner/Investigator modules. Production returns explicit `not_implemented` responses for those capabilities. It does not substitute fixtures or invoke the old inline Investigator against unavailable diagnostics. Complete the handoff in `integration/bindings.jac` when those typed exports are available. See [Member 3 integration](docs/MEMBER3_INTEGRATION.md).

## Run locally

Use **Jac 0.34.19**, matching the exact pin in `jac.toml`.

```sh
jac --version
jac install
jac check main.jac
jac check . --nowarn
jac start --dev main.jac
```

Open [localhost:8000](http://localhost:8000). Development mode uses a separate API port, normally 8001. Jac's Vite frontend may also advertise a LAN address.

Jac 0.34.19 does not support the newer `--frozen` install flag. The team's committed `jac.lock` is retained unchanged. In this runtime, the npm entry records a checksum rather than the contents of Bun's lockfile; obtain a teammate's matching `.jac/client/bun.lock` when exact npm-version alignment is needed. Avoid dependency updates while integrating features.

## Provider configuration

If needed, copy `.env.example` to `.env` and supply a real provider credential locally. Preserve an existing `.env`; never commit it. Load it before starting Jac:

```sh
set -a
. ./.env
set +a
jac start --dev main.jac
```

The existing bounded Gemini declaration remains in `operations.jac` until Member 2's module is available, as required by the work plan. Model and diagnostic configuration alone does not connect an Investigator implementation. Public wrappers use the production feature bindings; no model calls are made when the feature is unbound.

## Architecture

| Layer | Responsibility |
| --- | --- |
| `dashboard/atoms/` | Buttons, status badges, metrics |
| `dashboard/molecules/` | Feedback, empty states, graph nodes and relationships |
| `dashboard/organisms/` | Top bar, overview, graph, and feature panels |
| `dashboard/pages/SymphonyDashboard.jac` and its implementation annex | Page composition, state ownership, request orchestration |
| `dashboard/models/view_models.cl.jac` | Typed presentation models, JSON decoding, request guards |
| `operations.jac` | Stable public endpoint signatures; delegates to the gateway |
| `integration/gateway.jac` | Request validation, response checks, run and trace-evidence validation |
| `integration/ports.jac` | Injectable feature contracts for production and isolated tests |
| `integration/bindings.jac` | Single production composition root for Member 1/2 exports |
| `contracts.jac` | Unchanged shared integration records |

State flows down through typed props; actions flow up through callbacks. Result decoding stays out of visual components. External requests, feature execution, and model access stay server-side. No additional frontend or backend framework is introduced.

## Verification

```sh
jac test tests/dashboard_integration_tests.jac dashboard/models/view_models.cl.jac -v
jac fmt dashboard integration operations.jac tests --check
jac check main.jac
jac check . --nowarn
jac build --client web
```

Components explicitly return JSX for Jac 0.34.19 compatibility. The presentation test annex (`dashboard/models/view_models.cl.test.jac`) runs with the client module under Jac’s Bun runner; backend tests run on the server. Keep this convention in atoms, molecules, organisms, pages, and preview components.

The tests exercise input validation, unbound features, fixture incident/reset adapters, scan error classes, trace-supported discovery, stale-response guards, recovery non-mutation, and provider exceptions without model/API access.

For interactive verification against fixtures, stop the main server and run:

```sh
jac start --dev --port 8010 dashboard_preview.jac
```

Open [localhost:8010](http://localhost:8010). This separate application is visibly labeled **Fixture preview — no live scans or model calls**. Choose a response case and press Apply fixture mode. The `slow` case supports testing reset and selection races. The root preview entry is required because Jac 0.34.19 resolves web assets relative to the entry file. It rewrites the local client build, so restart `main.jac` afterward to return to production behavior. It is never imported by `main.jac` and must not be deployed as the real app.

## Truthfulness rules

- The inventory is simulated; real OSV lookups require Member 2's scanner.
- API failures never appear as verified zero-vulnerability results.
- The hidden Payment-to-Auth dependency is absent from initial state.
- Discovered relationships need matching request-trace evidence for the active run.
- Dependency reach means potential exposure; it does not establish compromise.
- Recovery preview must not mutate the active incident.

See [implementation plan](docs/IMPLEMENTATION_PLAN.md) and [work allocation](docs/WORK.md).
