# Agent integration checkpoint

Server integration modules use explicit `.sv.jac` placement so Jac 0.34.19 cannot pull locks or private fact storage into client bundles. Dotted import names and public operations remain unchanged.

The dashboard and application adapters implement WP3/WP4 of [the accepted plan](AGENTS_PLAN.md). The `security_analyst/` and `recovery_agent/` exports from `origin/feat/agents-member1` are connected through `integration/live_agents.sv.jac`, together with the action-aware simulator preview. Production never selects the preview providers.

## Composition and handoff protocol

`integration/agent_ports.sv.jac` defines `AgentPorts`. `production_ports()` in `integration/bindings.sv.jac` selects the real agents by default. Explicit `production_ports(agents)` overrides support isolated tests; `AgentPorts()` deliberately disables both agents. `integration/live_agents.sv.jac` adapts the feature exports to these callbacks:

```jac
AgentPorts(
    security=security_runner,
    recovery=recovery_runner,
    repair_options=list_repair_options,
    preview=preview_action
)
```

The callable signatures are:

- `security_runner(session: AgentSession) -> OperationEnvelope`
- `recovery_runner(session: AgentSession) -> OperationEnvelope`
- `list_repair_options() -> list[str]`
- `preview_action(service_id: str, action: str) -> OperationEnvelope`

Existing agent exports with different signatures should receive small explicit adapters here; feature implementation remains in its own module. No dynamic imports or silent fixture fallback are used. A missing export returns a specific failed envelope after prerequisite validation. New endpoints are registered explicitly in `main.jac`.

Every runner receives a **new** `AgentSession`, including `simulation_run_id`, selected `service_id` (Security Analyst only), a copied fact snapshot, and a session-local tool timeline. `session.read(name)` logs the read and returns a deep copy; the binding reads each prerequisite once and passes it to the feature. Feature tools use a second copied record held in a `ContextVar`, scoped to that invocation and restored in `finally`. Concurrent calls cannot mix tool results or timelines, and neither new agent requires a session-wide mutex. No recorder in `investigation/tools.jac` is reused.

Security fact names are `scan_results` (the latest OperationEnvelope for the selected service), `impact` (deterministic OperationEnvelope), and `known_dependencies` (public known links). Recovery fact names are `investigation_result` (latest completed evidence-backed OperationEnvelope), `impacts` (service ID to deterministic impact data), and `repair_options` (supported action strings). No root fault or private graph is supplied. Agents may run additional read-only previews in their own session implementation; the integration layer always verifies the final decision independently.

Runner results use the existing frozen `SecurityAssessment` or `RecoveryProposal` field names, flattened into `OperationEnvelope.data`. They must carry the captured run ID; assessments also carry the selected service ID. Preserve specific provider/tool error codes in failed envelopes. Unexpected exceptions receive an agent-specific execution error. The adapters do not call a model directly or configure an extra provider.

**Jac 0.34.19 model schema constraint:** `RepairPreview.before/after` contain `dict[str, any]`, which byLLM cannot generate as a typed schema. Use a narrow internal model decision containing only target, action, rationale, and cited evidence IDs. The adapter stamps the run and replaces `preview` with the simulator’s returned before/after/outcome; never ask the model to generate the authoritative preview.

## Storage, prerequisites and reset

`integration/result_store.sv.jac` is a process-local repository protected by a lock. The gateway records validated scan and Investigator responses, as well as agent results, with run and request revisions. Beginning a new scan removes the previous assessment; beginning an investigation removes the previous recovery proposal. Failed scans replace prior successful inputs, so an old clean result cannot be reused. A pending prerequisite is unavailable until its response is committed.

Missing prerequisites return `scan_required` or `investigation_required`. A failed scan returns `scan_failed`; partial scans may be assessed but retain `partial` status and an explicit incomplete-coverage error. An incomplete scan cannot support an all-clear claim. Failed/partial investigations cannot authorize recovery.

Run checks surround runner calls. Input revisions and graph revisions are checked after execution and again during the final repository commit. Reset or incident changes clear all stored run-specific results. Older requests cannot overwrite newer results. Long runner/model calls do not hold the simulator or repository lock. Concurrent analyst sessions are tested with two actual threads and independent session records.

State remains in one server process. This does not introduce multi-worker persistence or deployment configuration.

## Validation and deterministic fallback

Assessments must cover every current advisory/package pair and cite current-scan advisory IDs. Repeated advisory IDs affecting several packages are handled separately. Dependent services must match deterministic impact; unsupported vulnerability/compromise claims about dependents are rejected. `rule_based_priority` is overwritten from deterministic impact, while `priority_below_rule_based` flags a lower model priority. Model priority labels are trimmed and case-normalized; `critical` maps to the application’s highest priority, `high`, with an explanation of that mapping. Unknown labels still fail validation. OSV advisory severity remains unchanged. Partial coverage is exposed as `scan_status` plus a partial envelope; these presentation metadata fields do not change the frozen records.

Recovery decisions must use a public service, a listed action, a nonempty rationale, and evidence IDs from the current completed investigation. The adapter calls the action-aware simulator preview and replaces any model-supplied preview. `not_recovered` and `no_incident` are successful verification outcomes, not evidence of recovery. The callback contract requires copied-state, read-only execution; `auth_outage` recovers with `restart` on `auth`; `payment_outage` recovers with `rollback` on `payment`. Wrong targets, other actions and `failover` return `not_recovered`. With no active incident the agent returns `failed/no_active_incident`; the manual preview still supports `no_incident`.

The Security panel separates model priority from deterministic priority. Zero-advisory assessments use `analysis_source=deterministic`, use rule-based priority, make no model call, and are labeled accordingly. A typed agent failure still allows a fresh deterministic impact request. The Recovery panel separates model-authored target/rationale/citations from the reused deterministic comparison table. Existing manual impact and recovery controls remain available. New scan/investigation attempts invalidate dependent UI output immediately; service/run/request guards discard obsolete responses.

## Verification

Run from the repository root. Use a fresh Jac process for each suite: Jac 0.34.19 imports feature test annexes into integration collections, and combining every suite in one process can leave byLLM nested types such as `AssessedFinding` bound to another collection’s namespace. Serial isolated runs exercise the same tests without that runner collision.

```sh
for suite in tests/feature_integration_tests.jac tests/agent_integration_tests.jac \
  tests/agent_workflow_tests.jac tests/dashboard_integration_tests.jac \
  dashboard/models/view_models.cl.jac recovery_agent/agent.jac \
  recovery_agent/validation.jac security_analyst/agent.jac \
  security_analyst/validation.jac investigation/agent.jac \
  investigation/validation.jac simulation/fixtures.jac; do
  JAC_TEST_JOBS=0 jac test "$suite" || break
done
jac check main.jac
jac check . --nowarn
jac fmt dashboard integration main.jac dashboard_preview.jac tests/agent_integration_tests.jac tests/dashboard_fixtures.jac --check
jac build --client web
```

MockLLM checks cover chaining, advisory/evidence provenance, empty/partial/failed scans, both incidents, wrong repairs, reset and replacement-input races, session isolation and provider failures. Client tests cover separate priorities, partial coverage, citation decoding, failed verification and independent request counters. These checks do not consume Gemini quota and do not establish live agent quality.

Use the explicitly labeled `dashboard_preview.jac` entry for completed, empty, partial, failed, unavailable and slow UI fixtures. Stop it and rebuild/restart `main.jac` after verification because both entries share the generated client directory. The real production bindings, all three agents and actual simulator tools are exercised together with MockLLM for both incidents. Only OSV transport and model providers are replaced; offline tests never substitute the completed agent features. Live Gemini quality and deployment remain separately configured acceptance work.

Current integration verification is recorded in the merge description. The offline workflow suite covers both incidents, advisory/evidence citations, action-aware verification, partial no-advisory assessments, authentication failures, reset clearing, concurrent real tool sessions and swallowed tool errors. No live model requests are made. `jac.lock`, dependency manifests and frozen contracts are unchanged by this integration.

Verified integration: 433 passing test executions across the 12 isolated suites, three opt-in OSV skips, 80 passing Jac static checks, formatting checks and a successful production client build. Production HTTP checks cover all 12 registered operations, missing prerequisites, deterministic impact/recovery and reset. Browser acceptance exercises the real production composition and all three agent/tool implementations with MockLLM and offline OSV transport, displaying advisory/evidence citations, separate priorities, trace-backed discovery and a simulator-verified recovered proposal. Temporary provider overrides are removed after verification and the normal app is rebuilt.
