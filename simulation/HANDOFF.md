# Simulation handoff (Member 1 -> Member 3)

Branch: `feat/graph-simulation`. No shared files (`operations.jac`, `main.jac`, `contracts.jac`) were modified.
All functions return `OperationEnvelope` (`status`, `data`, `error`) unless noted. Failures use `status="failed"`
with `error.code`; there is no fake success.

## Wiring table

| Public wrapper in `operations.jac` | Feature function | Import from |
| --- | --- | --- |
| `get_dashboard_state()` | `sim_dashboard_state() -> DashboardState` | `simulation.state` |
| `start_incident(incident_id)` | `sim_start_incident(incident_id: str)` | `simulation.state` |
| `reset_incident()` | `sim_reset()` | `simulation.state` |
| `check_service_health(service_id)` | `sim_check_health(service_id: str)` | `simulation.diagnostics` |
| `get_service_logs(service_id)` | `sim_get_logs(service_id: str)` | `simulation.diagnostics` |
| `trace_requests(service_id)` | `sim_trace_requests(service_id: str)` | `simulation.diagnostics` |
| `analyze_security_impact(service_id)` | `sim_analyze_impact(service_id: str)` | `simulation.impact` |
| `preview_recovery(service_id)` | `sim_preview_recovery(service_id: str)` | `simulation.recovery` |

Helpers for the investigator/integration layer (`simulation.state`):

- `sim_accept_discovered_dependency(source_id, target_id, evidence_ids: list[str])` — validates and records a
  discovered edge. Returns the `Dependency` dict on success. Error codes: `unknown_service`, `missing_evidence`,
  `already_known`, `unknown_or_stale_evidence`, `unsupported_evidence`, `evidence_does_not_support_edge`.
- `sim_is_current_run(run_id: str) -> bool` — use to drop stale async/UI results after a reset.

## Result shapes (`data` when `completed`)

- `sim_start_incident`: `incident_id`, `services` (`[{id, name, state}]`), `simulation_run_id`.
  Unknown incident -> `failed`, code `unknown_incident`.
- `sim_reset`: `incident_id="normal"`, `services`, `dependencies` (five documented, `evidence_ids` empty),
  new `simulation_run_id`.
- `sim_check_health` / `sim_get_logs` / `sim_trace_requests`: one Evidence record flattened into `data`:
  `id`, `tool`, `service_id`, `observation`, `simulation_run_id`.
  - health observation: `state`, `http_status`, `error_rate_pct`, `latency_ms` (None when down)
  - logs observation: `entries` = `[{level, message}]`
  - trace observation: `spans` = `[{direction: incoming|outgoing, peer, outcome: ok|timeout|error_503|not_attempted}]`
- `sim_analyze_impact`: `service_id`, `dependent_services`, `relationships` (Dependency dicts),
  `potential_exposure` (cautious sentences), `priority` (`low|medium|high`).
- `sim_preview_recovery`: `service_id`, `candidate_repair`, `before`, `after` (both `[{id, name, state}]`),
  `outcome` (`recovered | not_recovered | no_incident`). Does not mutate the active incident.
- `sim_dashboard_state` returns a `DashboardState` with live service states, documented plus accepted
  discovered dependencies, a populated summary, and the current `simulation_run_id`.

## Behavior notes

- Run IDs are `run-1`, `run-2`, ... per start/reset. Before any call it is `"initial"`.
- Evidence IDs are `<run_id>-ev-<n>` and are cleared on every start/reset, so old evidence is rejected.
- Diagnostics never include the injected fault or the true graph. Only traces reveal observed calls, which
  is how Payment -> Auth is discoverable during `auth_outage`.
- Incident scenarios: see `incidents.jac`. `degraded` is supported by the contract but no rules produce it.

## Fixtures (`simulation/fixtures.jac`)

Static, no live state; run ID is `"fixture-run"`. Verified against the live simulation in `fixtures.test.jac`.

- `fixture_start_incident(incident_id)` for `normal`, `auth_outage`, `payment_outage`
- `fixture_reset()`
- `fixture_health(service_id, incident_id)`
- `fixture_auth_outage_payment_trace()` — the trace evidence that supports Payment -> Auth
- `fixture_unknown_service()` — the invalid-service error envelope

## Verifying

```bash
jac check main.jac
jac fmt simulation/ --check
jac test simulation/state.jac   # likewise diagnostics, impact, recovery, fixtures
```
