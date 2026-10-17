# SYMPHONY

Agentic Reliability & Security Intelligence

> Uncover hidden dependencies. Investigate failures. Expose vulnerabilities.

SYMPHONY is a Jac full-stack foundation for a hackathon demo that combines a simulated microservice topology, evidence-driven incident investigation, and real OSV.dev advisory lookups.

## Current phase

The foundation currently provides:

- A responsive Jac dashboard with all required product panels.
- Six services and five documented dependencies.
- Stable typed contracts for all three workstreams.
- Exact-version simulated software inventories.
- A working `get_dashboard_state()` server endpoint.
- Explicit server placeholders for every planned operation.
- Client adapters already wired to those operation names.

Incident simulation, Jac byLLM investigation, and real OSV scanning are intentionally marked as not connected. Their buttons call real placeholder endpoints and never show fake success data.

The Investigator's byLLM declaration and tool boundary are wired. The checked-in example credential is deliberately invalid, so model calls return an explicit failure until a real provider key is supplied.

## Run locally

Install the current Jac toolchain, then run:

```bash
jac install
jac check main.jac
jac run --dev main.jac
```

Open `http://localhost:8000`.

## Configure the Investigator

Copy the example environment file and replace its dummy key:

```bash
cp .env.example .env
```

```text
GOOGLE_API_KEY=your-real-gemini-key
LLM_MODEL=gemini/gemini-3.8-flash
LLM_FALLBACK_MODEL=gemini/gemini-3.1-flash-lite
```

`.env` is ignored by Git. Load it into the shell that starts Jac so the key and
model choices override the safe defaults:

```bash
set -a
source .env
set +a
jac run --dev main.jac
```

The Investigator uses `gemini-3.8-flash` first and falls back to
`gemini-3.1-flash-lite` after a bounded retry. Each request has a 45-second
timeout. It is bounded to six ReAct iterations and can call only
`check_service_health`, `get_service_logs`, and `trace_requests`. Malformed
structured output receives at most one corrective retry to avoid unnecessary
quota consumption.

## Project structure

```text
main.jac                         Application entry and endpoint registration
contracts.jac                    Shared typed integration contracts
catalog.jac                      Six-service inventory and documented graph
operations.jac                   Public operation surface and honest stubs
dashboard/
  SymphonyDashboard.jac          Stateful dashboard shell
  SymphonyDashboard.impl.jac     Async operation handlers
  TopBar.jac                     Product identity
  SystemOverview.jac             Summary metrics
  DependencyGraph.jac            Fixed documented topology
  IncidentPanel.jac              Simulation controls
  InvestigationPanel.jac         Agent evidence timeline surface
  SecurityPanel.jac              OSV scan controls and results surface
  RecoveryPanel.jac              Impact and recovery placeholders
styles.css                       Global visual system and responsive layout
IMPLEMENTATION_PLAN.md           Scope, architecture, schedule, and contracts
WORK.md                          Parallel assignments and merge gates
```

## Parallel development

Each workstream can develop without waiting for another:

- Graph work replaces incident and diagnostic stubs in `operations.jac` or moves them into a feature module while preserving signatures.
- Security work replaces `scan_service_dependencies()` and `run_investigation()` while using the existing contracts.
- Dashboard work develops against the current endpoint results and can add fixtures for completed states.

If an operation moves to a feature module, keep it imported by `main.jac` so Jac registers its public endpoint. Do not rename required fields without coordinating all three branches.

## Truthfulness rules

- The software inventory is simulated; advisory lookup will be real.
- API failures must never appear as zero vulnerabilities.
- The hidden Payment-to-Auth dependency must not be returned in initial dashboard state.
- Agent conclusions must cite diagnostic evidence.
- Downstream services are potentially exposed, not automatically vulnerable or compromised.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) and [WORK.md](WORK.md) for the full build plan.
