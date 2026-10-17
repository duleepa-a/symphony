# Member 3 integration handoff

## Implemented boundary

`operations.jac` retains all original operation names and signatures. `contracts.jac` and the team's `jac.lock` are unchanged. No feature-owner directories are modified.

`FeaturePorts` separates the dashboard/application boundary from feature implementations:

- `dashboard`: optional `Callable[[], DashboardState]`.
- `handlers`: operation-name to synchronous `Callable[..., OperationEnvelope]`.

Bind actual exports in `integration/bindings.jac`. Production currently returns an empty `FeaturePorts` because those modules are absent from this branch. The gateway returns the initial catalog only when a dashboard provider is unbound. An installed provider that fails is not silently replaced with healthy data.

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

A feature can be bound independently. Keep the others absent until ready. Move the existing inline byLLM declaration out of `operations.jac` only after Member 2 supplies its replacement, as specified in WORK.md.

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
- `observation.source_id` and `observation.target_id` match the proposed relationship.

The gateway rejects unsupported or stale discoveries. Adapt nested trace formats to these explicit source/target observations at the feature boundary after agreeing the shape with Member 1/2. The dashboard merges accepted discovered relationships into its visible graph without mutating the simulator's private graph.

### Impact and recovery

Impact uses `dependent_services` (IDs/names or service records), `relationships` (strings or Dependency records), `potential_exposure`, and `priority`.

Recovery uses `candidate_repair`, `before`, `after`, and `outcome`. Before/after are lists of records with `id` (or `service_id`) and `state`. Missing after-state is shown as `unknown`; it is never inferred to be healthy.

## Request lifecycle

The page keeps a typed `RequestScope` in a persistent `Ref`: generation counter, independent operation request IDs, current service/run, and incident-mutation guard. Jac 0.34.19 event closures retain old reactive-state snapshots, so lifecycle checks read this ref after every await. Incident/reset requests invalidate the old generation immediately. A service change clears and invalidates only the service-specific panels. Long operations refresh the server snapshot before applying results so changes made by another caller also invalidate stale results. A request may only update a panel while its generation, request ID, selected service, and simulation run still match.

User actions and authoritative dashboard snapshots clear Jac 0.34.19’s RPC read cache so indirectly invoked feature adapters cannot return cached previous-run data.

The gateway independently checks the run before and after feature execution. This is a defensive adapter check, not a replacement for the simulator's concurrency or evidence lifecycle rules.

## Verification and remaining checkpoint

`tests/dashboard_fixtures.jac` contains deterministic **test doubles**, not Member 1/2 implementations. `dashboard_preview.jac` explicitly activates them and displays a fixture banner. `main.jac` never imports the preview entry or its fixture providers. Explicit `sv` blocks keep feature execution and test providers on the server. Presentation helpers are explicitly client-side in `view_models.cl.jac`; their client test annex runs under Bun.

After integrating real feature branches, rerun Jac checks, tests, client build, HTTP operation checks, and both incident workflows in the browser. Real OSV transport, live Gemini quality, and real simulator reset/evidence behavior remain the feature owners' acceptance gates; fixture passes do not establish those capabilities.
