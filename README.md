# SYMPHONY

Agentic Reliability & Security Intelligence

> Uncover hidden dependencies. Investigate failures. Expose vulnerabilities.

SYMPHONY is a Jac 0.34.19 full-stack application for investigating a simulated six-service topology. The service inventory is simulated. OSV advisory lookups use the real API; the bounded Gemini Investigator uses the simulator’s real diagnostic tools.

## Dashboard

The dashboard now provides:

- Independent incident, investigation, scan, impact, and recovery states, including loading, completed, empty, partial, failed, and unavailable outcomes.
- A selectable six-service graph driven by returned service health and dependencies, with separate documented and trace-backed discovery styles and an accessible relationship list.
- Investigation timeline, observed evidence, ranked candidates, discovered relationships, and explanation.
- Package-level advisory results, external references, unknown severity, and explicit incomplete/error coverage.
- Potential-exposure analysis and a non-destructive recovery comparison.
- Run/request/service guards that reject stale responses after reset, a new incident, or selection changes.
- Keyboard-visible focus, a skip link, live status feedback, reduced-motion support, and a horizontally scrollable graph on narrow screens.

**Integration status:** Member 1’s simulator, diagnostics, impact, and recovery modules and Member 2’s scanner and Investigator are connected through `integration/bindings.sv.jac`. No production port uses fixture data. Accepted trace-backed discoveries persist in the public simulation graph and affect impact analysis. Reset creates a new run and clears discoveries/evidence. See [integration details](docs/DASHBOARD_INTEGRATION.md).

## Security Analyst and Recovery proposals

The dashboard now includes model-labeled risk assessments beside deterministic priority, and repair proposals beside simulator verification. Scans and investigations are chained by simulation run; reset and replacement inputs invalidate dependent output. Agent sessions are independent and provider failures retain manual impact/recovery fallback.

The Security Analyst and Recovery agents are connected to the production gateway. Security uses the latest service scan; Recovery uses the latest evidence-backed investigation and independently verified repair preview. See [agent integration and validation](docs/AGENT_INTEGRATION.md) for session isolation, failure handling and offline verification.

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

After changing server validation, diagnostic tools, agent bindings, or provider configuration, stop Jac with Ctrl+C and start it again. Refreshing the browser alone can leave imported server code from the previous process active. Restarting clears the process-local simulation and investigation results; trigger the incident and investigate again.


Jac 0.34.19 does not support the newer `--frozen` install flag. The team's committed `jac.lock` is retained unchanged. In this runtime, the npm entry records a checksum rather than the contents of Bun's lockfile; obtain a teammate's matching `.jac/client/bun.lock` when exact npm-version alignment is needed. Avoid dependency updates while integrating features.

## Provider configuration

If needed, copy `.env.example` to `.env` and supply a real provider credential locally. Preserve an existing `.env`; never commit it. Load it before starting Jac:

```sh
set -a
. ./.env
set +a
jac start --dev main.jac
```

Production connects the Investigator, Security Analyst and Recovery agents. Their bounded Gemini declarations live in their respective `agent.jac` modules; the new agents share configuration in `agent_support/models.jac`. Model/provider configuration uses the existing `LLM_MODEL`, `LLM_FALLBACK_MODEL`, and `GOOGLE_API_KEY` settings. Provider failures return explicit failed envelopes. Deterministic verification uses MockLLM and does not consume Gemini quota; live Gemini response quality has not been verified during integration.

## Architecture

| Layer | Responsibility |
| --- | --- |
| `dashboard/atoms/` | Buttons, status badges, metrics |
| `dashboard/molecules/` | Feedback, empty states, graph nodes and relationships |
| `dashboard/organisms/` | Top bar, overview, graph, and feature panels |
| `dashboard/pages/SymphonyDashboard.jac` and its implementation annex | Page composition, state ownership, request orchestration |
| `dashboard/models/view_models.cl.jac` | Typed presentation models, JSON decoding, request guards |
| `operations.jac` | Stable public endpoint signatures; delegates to the gateway |
| `integration/gateway.sv.jac` | Request validation, response checks, run and trace-evidence validation |
| `integration/ports.sv.jac` | Injectable feature contracts for production and isolated tests |
| `integration/bindings.sv.jac` | Single production composition root for real feature exports |
| `integration/*_adapter.sv.jac` | Payload translation, short simulator locks, serialized Investigator sessions and run-safe discovery acceptance |
| `simulation/` | Private deterministic incidents, diagnostics, public known graph, impact and copied-state recovery |
| `security/`, `investigation/`, `security_analyst/`, `recovery_agent/` | OSV transport, bounded byLLM agents, isolated tool sessions and evidence validation |
| `contracts.jac` | Unchanged shared integration records |

State flows down through typed props; actions flow up through callbacks. Result decoding stays out of visual components. External requests, feature execution, and model access stay server-side. No additional frontend or backend framework is introduced.

## Verification

The client model suite must remain at `dashboard/models/view_models.cl.test.jac`: Jac 0.34.19’s Bun runner emits a standalone test harness without compiling its relative client-module dependencies. Moving the suite to `tests/` was verified to fail all nine cases with `Cannot find module '../dashboard/models/view_models.js'`. The matching annex filename is required; its test cases use descriptive names without ownership prefixes. Standalone suites and preview helpers in `tests/` use descriptive filenames.

```sh
for suite in tests/feature_integration_tests.jac tests/agent_integration_tests.jac \
  tests/agent_workflow_tests.jac tests/dashboard_integration_tests.jac \
  dashboard/models/view_models.cl.jac recovery_agent/agent.jac \
  recovery_agent/validation.jac security_analyst/agent.jac \
  security_analyst/validation.jac investigation/agent.jac \
  investigation/validation.jac simulation/fixtures.jac; do
  JAC_TEST_JOBS=0 jac test "$suite" || break
done
# Optional real OSV acceptance (no Gemini call):
RUN_LIVE_OSV_TESTS=1 jac test security/osv.jac --test_name "real OSV lookup is available when explicitly enabled"
jac fmt dashboard integration operations.jac tests --check
jac check main.jac
jac check . --nowarn
jac build --client web
```

Components explicitly return JSX for Jac 0.34.19 compatibility. The presentation test annex (`dashboard/models/view_models.cl.test.jac`) runs with the client module under Jac’s Bun runner; backend tests run on the server. Keep this convention in atoms, molecules, organisms, pages, and preview components.

The suites exercise feature-owner tests plus real cross-feature incident/reset flows, MockLLM discovery through native trace spans, discovery persistence into impact analysis, reset races, scanner payload translation, provider errors, and client request guards. `JAC_TEST_JOBS=0` avoids Jac 0.34.19’s nondeterministic parallel collection of imported test annexes. Simulation state is process-local: run one server process for this implementation; shared persistence and multi-worker deployment are outside this integration.

For interactive verification against fixtures, stop the main server and run:

```sh
jac start --dev --port 8010 dashboard_preview.jac
```

Open [localhost:8010](http://localhost:8010). This separate application is visibly labeled **Fixture preview — no live scans or model calls**. Choose a response case and press Apply fixture mode. The `slow` case supports testing reset and selection races. The root preview entry is required because Jac 0.34.19 resolves web assets relative to the entry file. It rewrites the local client build, so restart `main.jac` afterward to return to production behavior. It is never imported by `main.jac` and must not be deployed as the real app.

## Truthfulness rules

- The inventory is simulated; advisories come from Member 2’s real OSV scanner.
- API failures never appear as verified zero-vulnerability results.
- The hidden Payment-to-Auth dependency is absent from initial state.
- Discovered relationships need matching request-trace evidence for the active run.
- Dependency reach means potential exposure; it does not establish compromise.
- Recovery preview must not mutate the active incident.

See [implementation plan](docs/IMPLEMENTATION_PLAN.md) and [work allocation](docs/WORK.md).
