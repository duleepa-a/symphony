# Dashboard integration handoff

## Implemented boundary

`operations.jac` retains all original operation names and signatures. `contracts.jac` and the team's `jac.lock` are unchanged. The feature-owner changes are limited to shared native-span validation, stricter simulator evidence acceptance, and explicit nested byLLM type imports required by Jac 0.34.19.

`FeaturePorts` separates the dashboard/application boundary from feature implementations:

- `dashboard`: optional `Callable[[], DashboardState]`.
- `handlers`: operation-name to synchronous `Callable[..., OperationEnvelope]`.

Actual feature exports are bound in `integration/bindings.sv.jac`. The simulator adapter serializes short state operations. Security adapters translate findings/advisory IDs and per-package errors without changing completion status. The Investigator adapter binds real diagnostic tools, supplies only documented topology and visible states, attaches actual evidence, and persists validated discoveries in the simulator. The gateway returns the initial catalog only when a dashboard provider is unbound. An installed provider that fails is not silently replaced with healthy data.

Use explicit imports at the handoff; do not dynamically discover modules, fall back to fixture data, or rename the public endpoints. Synchronous feature handlers should encapsulate their own async client execution, or the gateway must be deliberately extended to await async ports before binding them. The current port contract is synchronous.

## Binding map

| Public operation | Feature-owner capability to bind |
| --- | --- |
| `get_dashboard_state` | Member 1 public simulation snapshot via the `dashboard` port |
| `start_incident`, `reset_incident` | Member 1 incident/reset exports |
| `check_service_health`, `get_service_logs`, `trace_requests` | Member 1 diagnostics |
| `run_investigation` | Member 2 validated Investigator operation |
| `scan_service_dependencies` | Member 2 scanner |
| `analyze_security_impact`, `preview_recovery` | Member 1 impact/recovery exports |

All ports are connected. The duplicate inline byLLM declaration has been removed from `operations.jac`; `investigation/agent.jac` is the sole production Investigator.

## Payloads consumed by the dashboard

The existing common envelope remains `OperationEnvelope(status, data, error)`. Success and partial payloads must include the fields in IMPLEMENTATION_PLAN.md. Presentation decoding accepts the plan's `timeline`/`candidates` names and the existing `tool_timeline`/`candidate_root_causes` names.

### Scans

`data` contains `service_id`, `inventory`, `packages`, and `finding_count`. Each package result supplies:

```text
name, ecosystem, version
status: completed | partial | failed
error: {message} | null
advisories: [{id, summary, severity, reference_url}]
```

`package` is also accepted as a string alias for `name`, and `url` for `reference_url`. Null or absent severity displays `unknown`. Only HTTP(S) advisory links are rendered. Empty successful package results are rejected as invalid coverage rather than displayed as a clean scan. Return one package result for each inventory item, including failed lookups. An adapter should map a feature's different internal representation into this wire shape.

### Investigation

Use `tool_timeline` (or `timeline`), `evidence`, `candidate_root_causes` (or `candidates`), `discovered_dependencies`, and `explanation`. Legacy `observed_evidence` strings can be displayed, but **cannot authorize new relationships**.

Every discovered relationship must reference an Evidence record in `data.evidence` whose:

- `id` appears in `evidence_ids`;
- `tool` is `trace_requests`;
- `simulation_run_id` matches the current snapshot;
- flat `observation.source_id`/`target_id` match, or a native span shows the corresponding outgoing/incoming peer for the inspected service;
- native span outcomes are `ok`, `timeout`, or `error_503`; `not_attempted` cannot establish a relationship.

`integration/evidence.jac` supplies the same matching rule to the gateway, feature validator, and simulator acceptance path. Every cited ID must match. Native observations remain intact; no evidence or hidden edge is invented by an adapter.

Investigator sessions are serialized because the supplied tool recorder is process-local. Diagnostic calls check the captured run before reading state. Network/model execution does not hold the simulator lock, so reset can proceed. On return, validation and discovery acceptance run under the simulator lock with a fresh run check. Stale investigations cannot populate a later run. Discoveries are idempotent when an edge is already known. Impact reads the resulting known graph; recovery remains a copied-state simulation.

### Impact and recovery

Impact uses `dependent_services` (IDs/names or service records), `relationships` (strings or Dependency records), `potential_exposure`, and `priority`.

Recovery uses `candidate_repair`, `before`, `after`, and `outcome`. Before/after are lists of records with `id` (or `service_id`) and `state`. Missing after-state is shown as `unknown`; it is never inferred to be healthy.

## Request lifecycle

The page keeps a typed `RequestScope` in a persistent `Ref`: generation counter, independent operation request IDs, current service/run, and incident-mutation guard. Jac 0.34.19 event closures retain old reactive-state snapshots, so lifecycle checks read this ref after every await. Incident/reset requests invalidate the old generation immediately. A service change clears and invalidates only the service-specific panels. Long operations refresh the server snapshot before applying results so changes made by another caller also invalidate stale results. A request may only update a panel while its generation, request ID, selected service, and simulation run still match.

User actions and authoritative dashboard snapshots clear Jac 0.34.19’s RPC read cache so indirectly invoked feature adapters cannot return cached previous-run data.

The gateway independently checks the run before and after feature execution. This is a defensive adapter check, not a replacement for the simulator's concurrency or evidence lifecycle rules.

## Verification

The client model suite must remain at `dashboard/models/view_models.cl.test.jac`: Jac 0.34.19’s Bun runner emits a standalone test harness without compiling its relative client-module dependencies. Moving the suite to `tests/` was verified to fail all nine cases with `Cannot find module '../dashboard/models/view_models.js'`. The matching annex filename is required; its test cases use descriptive names without ownership prefixes. Standalone suites and preview helpers in `tests/` use descriptive filenames.

`tests/feature_integration_tests.jac` exercises real production ports with both incidents, native diagnostic evidence, MockLLM discovery, persistent graph/impact updates, non-mutating recovery, reset races, scanner translation, and authentication failures. Existing feature and dashboard tests remain available. Use the serial command in README to avoid Jac 0.34.19’s imported-annex collection ordering issue.

Real OSV transport and HTTP advisory serialization were verified against the catalog’s exact lodash version. Live Gemini quality remains unverified; deterministic Investigator acceptance uses MockLLM without spending quota.

`tests/dashboard_fixtures.jac` remains an explicitly labeled UI test double, activated only by `dashboard_preview.jac`. Production does not bind those fixture providers. Presentation helpers and their test annex remain in the current atomic dashboard architecture.
