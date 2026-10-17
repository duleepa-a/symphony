# SYMPHONY Implementation Plan

## Goal

Build a runnable Jac full-stack application that demonstrates reliability and security investigation across a simulated six-service architecture. The required first release includes the dashboard, shared JSON-compatible contracts, sample service inventories, the documented dependency graph, and real server-side OSV.dev lookups.

The stretch release adds deterministic incidents and one evidence-driven Investigator Agent. It must never expose the simulator's hidden cause or true graph directly to the agent.

## Current implementation baseline

The planned P0-P2 implementation is complete and integrated:

- Jac project configuration, dependency lock, and application entry point.
- Shared contracts, stable service IDs, deterministic incidents, diagnostics, and recovery previews.
- Six-service catalog, documented and discovered graph edges, and simulated package inventories.
- Real OSV scanning with explicit success, partial-failure, and failure states.
- Evidence-driven Gemini investigation and security/recovery agents.
- Responsive dashboard wired to the live operation layer.
- Optional `SYMPHONY_SERVICE_MODE=real` integration for locally hosted microservices.

The real-service integration is a local demonstration extension. In real mode, health, logs, traces, and investigation read the configured service URLs. Docker controls service lifecycle, so the dashboard intentionally disables simulated incident and reset controls instead of claiming to change real containers.

## Implementation constraints

- Team size: exactly three members.
- Implementation window: eight hours.
- At least 80% of authored code must be Jac.
- The product must meaningfully use Jac and Jaseci.
- Each member must be able to implement and test their work without waiting for another branch.

## Delivery priorities

| Priority | Deliverable | Exit condition |
| --- | --- | --- |
| P0 | Jac dashboard and real OSV scanner | App starts, six services and five documented edges render, and OSV success/empty/error states work |
| P1 | Deterministic incidents and Investigator Agent | Auth and Payment scenarios propagate correctly; investigation uses diagnostic tools and evidence |
| P2 | Security impact and recovery preview | Graph impact uses known/discovered edges; recovery compares copied before/after state |

P0 is the functional baseline, P1 is complete, and P2 is implemented. Any future unfinished action must return an explicit `not_implemented` or `simulation_not_connected` status and must never claim success.

## Product scope

### System overview

Show total, healthy, failed and degraded services, discovered dependencies, and known vulnerability findings.

### Service dependency graph

Render six fixed-position nodes:

- Frontend
- API Gateway
- Payment
- Catalog
- Auth
- Database

Render these documented dependencies:

- Frontend depends on API Gateway.
- API Gateway depends on Payment.
- API Gateway depends on Catalog.
- Payment depends on Database.
- Catalog depends on Database.

The hidden Payment-to-Auth dependency exists only in the future simulator's private true graph. It must not appear initially or be included in agent context.

### Incident controls

Provide Normal operation, Auth outage, and Payment outage selections with Trigger Incident, Reset Simulation, and Investigate controls. Until connected, controls display `Simulation not connected` or `Not implemented yet`.

### AI investigation

Prepare investigation status, tool-call timeline, observed evidence, candidate causes, discovered connections, and explanation areas. Live output must be distinguished from placeholders. No scripted investigation may be presented as model output.

### Vulnerability scanning

Allow users to select a service and scan its simulated exact-version package inventory. The Jac server calls:

- `POST https://api.osv.dev/v1/query`
- `GET https://api.osv.dev/v1/vulns/{id}` when advisory details are needed

Display service, package, ecosystem, exact version, advisory ID, summary, available severity, reference URL, and scan status. Missing severity remains `unknown`. Timeouts, malformed responses, non-200 responses, and partial failures remain errors; they must not appear as zero findings.

Every inventory view carries the label `Simulated service inventory — real advisory lookup`.

### Security impact and recovery

Prepare security impact fields for the service with a finding, dependent services, known/discovered relationships, potential exposure, and priority. A dependent service must not be called vulnerable or compromised without direct evidence.

Prepare recovery fields for candidate repair, before/after state, and verification outcome. This remains an explicit placeholder unless P0 and P1 are stable.

## Architecture

Use small Jac modules with a single application entry point. Exact filenames may be adjusted to current Jac compiler requirements, but responsibilities stay separate.

| Area | Responsibility |
| --- | --- |
| App entry | Compose server operations and client dashboard |
| Shared contracts | Stable JSON-compatible records, IDs, enums, and operation shapes |
| Dashboard components | Layout, cards, graph, controls, panels, and state rendering |
| Graph simulator | Public documented graph, private true graph, incidents, propagation, reset |
| Diagnostics | Observable health, logs, and request traces generated from simulation state |
| OSV scanner | Server-side HTTP, normalization, timeout/error handling |
| Investigator | Tool orchestration, evidence collection, candidates, and explanation |

No React, Next.js, Express, separate Python application, database, authentication, Docker service, or Kubernetes cluster is required by the core submission. The optional real-service demo uses a separate Docker Compose project and communicates only through configured HTTP endpoints.

## Frozen integration contracts

These shapes are frozen before parallel work begins. Members may add optional fields but must not rename or remove required fields during the hackathon.

### Common envelope

Every operation returns a JSON-compatible object:

```text
{
  "status": "completed | running | partial | failed | not_implemented | simulation_not_connected",
  "data": object | list | null,
  "error": { "code": string, "message": string } | null
}
```

### Core records

```text
Service = {
  "id": string,
  "name": string,
  "state": "healthy | degraded | down"
}

Dependency = {
  "source_id": string,
  "target_id": string,
  "kind": "documented | discovered",
  "evidence_ids": [string]
}

PackageInventoryItem = {
  "name": string,
  "ecosystem": string,
  "version": string
}

Evidence = {
  "id": string,
  "tool": "check_service_health | get_service_logs | trace_requests",
  "service_id": string,
  "observation": object,
  "simulation_run_id": string
}
```

An edge means `source_id` depends on `target_id`. Failure therefore propagates from a failed target toward its source dependents.

### Operation boundaries

| Operation | Request | Required `data` fields when completed |
| --- | --- | --- |
| `get_dashboard_state()` | None | `services`, `dependencies`, `summary`, `simulation_run_id` |
| `start_incident(incident_id)` | `normal`, `auth_outage`, or `payment_outage` | `incident_id`, `services`, `simulation_run_id` |
| `reset_incident()` | None | Initial `services`, empty discovered edges, new `simulation_run_id` |
| `check_service_health(service_id)` | Stable service ID | One `Evidence` record |
| `get_service_logs(service_id)` | Stable service ID | One `Evidence` record |
| `trace_requests(service_id)` | Stable service ID | One `Evidence` record |
| `run_investigation()` | Current run | `timeline`, `evidence`, `candidates`, `discovered_dependencies`, `explanation` |
| `scan_service_dependencies(service_id)` | Stable service ID | `service_id`, `inventory`, `packages`, `finding_count` |
| `analyze_security_impact(service_id)` | Stable service ID | `dependent_services`, `relationships`, `potential_exposure`, `priority` |
| `preview_recovery(service_id)` | Stable service ID | `candidate_repair`, `before`, `after`, `outcome` |

Each member develops against local fixture data matching these contracts. No member waits for another member's implementation to build or test their own module.

## Deterministic behavior

| Scenario | Down | Healthy |
| --- | --- | --- |
| Normal | None | All six services |
| Auth outage | Auth, Payment, API Gateway, Frontend | Catalog, Database |
| Payment outage | Payment, API Gateway, Frontend | Auth, Catalog, Database |

Support `degraded` in the shared contract and UI, but do not add degradation rules unless all required work is stable.

The investigator can access only the three diagnostic operations. It cannot access the selected root fault, the private true graph, or internal propagation state. A discovered edge is accepted only when its `evidence_ids` reference runtime trace evidence.

## Eight-hour schedule

| Time | Parallel implementation outcome |
| --- | --- |
| Hours 0–2 | Member 1 builds deterministic simulation and diagnostics; Member 2 builds OSV and Investigator modules; Dashboard integration owner builds interactive dashboard state and fixture adapters |
| Hours 2–4 | Each member verifies their module independently against frozen contracts and supplies fixtures plus integration notes |
| Hour 4 | First integration checkpoint: Dashboard integration owner connects completed module APIs through the shared operation layer |
| Hours 4–6 | Members 1 and 2 fix module defects in their own branches while Dashboard integration owner completes live UI flows and stale-run handling |
| Hour 6 | Second integration checkpoint: verify P0 and the Auth and Payment incident paths end to end |
| Hours 6–8 | Harden error states, reset behavior, responsive UI, contract validation, and automated checks; implement P2 only if P0 and P1 are stable |

## Integration strategy

1. Each branch exposes only the frozen operations and records above.
2. Each workstream includes local fixtures or deterministic stubs so it can run alone.
3. The dashboard calls an adapter layer; switching from fixtures to live operations changes the adapter, not UI components.
4. The investigator calls diagnostic interfaces; its local fixtures use the same evidence records as the simulator.
5. The simulator does not import UI or investigator modules. The scanner does not import simulator state beyond service inventory passed through its operation.
6. Integration happens through small commits or cherry-picks at the two implementation checkpoints.
7. Contract changes require agreement from all three members and an immediate update to this document.

## Verification checklist

### P0 acceptance

- [x] The Jac project compiles and starts using the README command.
- [x] All six service nodes render at fixed positions.
- [x] Exactly five documented dependencies render initially.
- [x] The hidden dependency is absent from dashboard and network payloads.
- [x] A service can be selected and scanned.
- [x] At least one real server-side OSV request is observed.
- [x] Real findings, no-findings responses, partial failures, and complete failures are visibly distinct.
- [x] Missing severity is shown as unknown.
- [x] Incident and AI placeholders are honest and explicit if not connected.

### P1 acceptance

- [x] Both incident scenarios produce the deterministic states in this plan.
- [x] The agent receives only diagnostic tool output.
- [x] The investigation timeline reflects actual tool calls.
- [x] Payment-to-Auth is proposed only with supporting trace evidence.
- [x] Reset clears incident state, investigation results, and discovered edges.
- [x] Results from an old simulation run are rejected after reset.

### Implementation completion

- [x] All live operations validate inputs and return the frozen response envelope.
- [x] Module-level fixtures and checks run without requiring another member's branch.
- [x] No keys, tokens, generated caches, or build artifacts are committed.
- [x] Unfinished optional behavior remains disabled or returns an honest status.
- [ ] The integrated application compiles and its core flows work at desktop and mobile widths (final responsive visual pass pending).
