# SYMPHONY Remaining Implementation Work

This plan starts after the initial foundation implementation. It covers product implementation only. Demo recording, submission preparation, repository promotion, and deployment are intentionally deferred.

## Foundation already available

Do not rebuild these items:

- Jac 0.34.19 `web-app` project, dependency lock, and development commands.
- Typed contracts in `contracts.jac`.
- Six-service catalog, package inventories, and five documented dependencies in `catalog.jac`.
- Public operation names and truthful placeholder behavior in `operations.jac`.
- Responsive dashboard shell and required panels under `dashboard/`.
- Working `get_dashboard_state()` endpoint.
- Gemini byLLM configuration, bounded Investigator declaration, and safe provider-error handling.
- Ignored local `.env` and committed `.env.example`.

## Parallel-work rules

- Branches remain `feat/graph-simulation`, `feat/security-investigator`, and `feat/dashboard-integration`.
- Stable service IDs are `frontend`, `api_gateway`, `payment`, `catalog`, `auth`, and `database`.
- `contracts.jac` is frozen. Members may propose additive fields, but Dashboard integration owner applies agreed shared-contract changes during integration.
- `operations.jac`, `main.jac`, `jac.toml`, and `jac.lock` are integration-owned by Dashboard integration owner. Members 1 and 2 expose feature functions from their own modules and do not edit these shared files.
- Each feature module must be directly testable with local state or fixtures.
- No workstream waits for another workstream's branch. Cross-feature behavior is verified with fixtures until an integration checkpoint.
- Unfinished behavior returns `not_implemented`, `simulation_not_connected`, or `failed`; it never returns fake success.
- Keep external requests and model calls on the server.
- Never commit API keys, `.env`, `.jac/`, `node_modules/`, generated bundles, or runtime data.

## Ownership map

| Files or area | Owner | Other members |
| --- | --- | --- |
| `simulation/` and deterministic diagnostic generation | Member 1 | Read-only |
| `security/` and `investigation/` | Member 2 | Read-only |
| `dashboard/`, `operations.jac`, `main.jac`, shared configuration | Dashboard integration owner | Read-only outside agreed integration changes |
| `contracts.jac` | Dashboard integration owner integrates | Members 1 and 2 propose additive changes |
| `catalog.jac` | Member 1 | Member 2 consumes inventories read-only |

## Member 1 — Simulation, diagnostics, and graph impact

**Branch:** `feat/graph-simulation`

**Create or own:**

```text
simulation/
  state.jac
  incidents.jac
  diagnostics.jac
  impact.jac
  recovery.jac
  *.test.jac
```

### Core implementation

- [x] Implement an in-memory simulation state containing current incident, service states, discovered edges, and `simulation_run_id`.
- [x] Keep the complete true graph private inside the simulation feature.
- [x] Keep the public documented graph initially limited to the five existing dependencies.
- [x] Implement `normal`, `auth_outage`, and `payment_outage` scenarios.
- [x] Propagate failure from a failed dependency toward services that depend on it.
- [x] Implement reset with healthy states, no discovered edges, and a new run ID.
- [x] Expose feature functions for starting, reading, and resetting simulation state. Use feature-specific names so they do not collide with public wrappers in `operations.jac`.

### Diagnostic implementation

- [x] Generate deterministic health observations for each service.
- [x] Generate concise synthetic logs that expose symptoms without directly naming the hidden root fault.
- [x] Generate request traces that can reveal Payment-to-Auth during the Auth outage.
- [x] Return `Evidence` records carrying unique evidence IDs and the active `simulation_run_id`.
- [x] Reject unknown service IDs explicitly.
- [x] Ensure diagnostic output never serializes the true graph, private fault field, or internal propagation data.

### Graph impact and recovery

- [x] Implement reverse dependency traversal using documented plus accepted discovered edges.
- [x] Describe downstream services as potentially exposed or operationally affected.
- [x] Implement recovery preview against a copied simulation state so preview does not mutate the active incident.
- [x] Return before/after service states and a deterministic verification outcome.

### Independent verification

- [x] Normal state: all six services healthy.
- [x] Auth outage: Auth, Payment, API Gateway, and Frontend down; Catalog and Database healthy.
- [x] Payment outage: Payment, API Gateway, and Frontend down; Auth, Catalog, and Database healthy.
- [x] Auth traces support Payment depends on Auth without directly returning the true graph.
- [x] Reset invalidates evidence from the previous run.
- [x] Simulation tests run without dashboard, OSV, or Gemini access.

### Handoff to Dashboard integration owner

- Export one function for each public wrapper Dashboard integration owner must connect.
- Provide deterministic response fixtures for all scenarios and one invalid-service error.
- Document function signatures and expected result types in the branch handoff message.
- Do not modify `operations.jac` during the handoff.

## Member 2 — OSV scanner and evidence-driven Investigator

**Branch:** `feat/security-investigator`

**Create or own:**

```text
security/
  osv.jac
  normalization.jac
  *.test.jac
investigation/
  agent.jac
  validation.jac
  fixtures.jac
  *.test.jac
```

### OSV implementation

- [x] Read exact package inventories from `catalog.jac`; do not duplicate them.
- [x] Implement server-side `POST https://api.osv.dev/v1/query` calls.
- [x] Fetch `GET /v1/vulns/{id}` only when query results lack required display details.
- [x] Normalize advisory ID, summary, available severity, reference URL, package, ecosystem, and version.
- [x] Preserve missing severity as `unknown`.
- [x] Add request timeout and malformed-response handling.
- [x] Keep completed no-findings, partial failure, and complete failure states distinct.
- [x] Ensure an API failure can never become a completed zero-findings response.
- [x] Return one package-level result for every inventory item.

### Investigator implementation

- [x] Move the existing `investigate_incident` declaration from `operations.jac` into `investigation/agent.jac` during this branch's work; Dashboard integration owner performs the shared-file integration.
- [x] Keep Gemini as the configured provider and preserve the six-iteration limit.
- [x] Develop against diagnostic fixtures matching the frozen `Evidence` contract.
- [x] Give the model only documented topology, user-visible state, and diagnostic tools.
- [x] Record actual tool calls in order.
- [x] Return observed evidence, ranked candidates, discovered dependencies, and a concise explanation.
- [x] Accept a discovered dependency only when referenced request-trace evidence supports it.
- [x] Reject evidence whose `simulation_run_id` differs from the active run.
- [x] Return `failed` for authentication, quota, timeout, malformed-output, and tool errors.

### Independent verification

- [x] Verify at least one real OSV query against a known exact package version.
- [x] Verify a completed no-findings fixture.
- [x] Verify timeout, non-200, malformed, partial, and failed scan paths.
- [x] Test the Investigator with `MockLLM`; tests must not consume Gemini quota.
- [x] Verify unsupported model claims do not become discovered edges.
- [x] Verify the feature modules run without the dashboard or Member 1's branch.

### Handoff to Dashboard integration owner

- Export scanner and Investigator functions with documented typed returns.
- Provide scanner fixtures for completed findings, completed no findings, partial, and failed states.
- Provide Investigator fixtures for completed, failed, and stale-evidence states.
- Do not modify `operations.jac`, dashboard components, or shared configuration during the handoff.

## Dashboard integration owner — Dashboard behavior and integration

**Branch:** `feat/dashboard-integration`

**Owns:**

```text
dashboard/
operations.jac
main.jac
contracts.jac
jac.toml
jac.lock
README.md
```

### Dashboard implementation

- [x] Replace the single generic operation message with panel-specific state.
- [x] Render loading, completed, empty, partial, failed, and not-implemented states for each operation.
- [x] Connect incident selection, trigger, and reset to live wrappers when Member 1 is integrated.
- [x] Update graph node states after incident operations.
- [x] Render investigation tool timeline, evidence, candidates, explanation, and discovered edges.
- [x] Visually distinguish documented edges from evidence-backed discovered edges.
- [x] Render package-level OSV results with advisory links and `unknown` severity where needed.
- [x] Add a security-impact section that avoids unsupported vulnerable/compromised wording.
- [x] Render recovery before/after state and verification outcome.
- [x] Ignore stale asynchronous responses after the simulation run changes.
- [x] Preserve responsive layout, keyboard focus, and reduced-motion behavior.

Dashboard behavior now uses the integrated simulator, scanner, and Investigator through the stable public wrappers. The current atomic dashboard architecture is retained. Isolated, labeled fixtures remain available for UI state verification. See [integration details](DASHBOARD_INTEGRATION.md) for bindings and payload translation.

### Integration ownership

- [x] Import Member 1's feature functions and connect the public simulation/diagnostic wrappers in `operations.jac`.
- [x] Import Member 2's feature functions and connect scanner/Investigator wrappers.
- [x] Move the current inline Investigator code out of `operations.jac` after Member 2's module is available.
- [x] Apply only agreed additive contract changes.
- [x] Keep public operation names and response envelopes stable.
- [x] Resolve integration conflicts in shared files rather than asking feature branches to edit them.

Both feature branches are merged and their production exports are bound explicitly. Shared contracts, Jac 0.34.19, and the team lockfile remain unchanged. No shared-file merge conflicts or contract additions were needed. Necessary feature integration fixes share native-span evidence validation and import nested byLLM result types explicitly.

### Application verification

- [x] Run full-project `jac check . --nowarn` and formatting checks.
- [x] Build the production client bundle.
- [x] Start the application and verify every public operation over HTTP.
- [x] Verify all six nodes and exactly five initial documented edges.
- [x] Verify hidden relationships are absent before evidence-backed discovery.
- [x] Verify reset clears incident, investigation, impact, recovery, and discovered-edge UI state.
- [x] Verify provider and OSV failures remain visible and truthful.
- [x] Update README architecture and run instructions to match the integrated implementation.

Integration verification: the serial regression command in README exercises the feature tests, six cross-feature acceptance tests, seven existing dashboard server tests, and nine client tests with no live Gemini calls. Jac 0.34.19 may collect imported feature test annexes more than once; execution counts include those collected instances. Use `JAC_TEST_JOBS=0` to avoid nondeterministic parallel collection ordering.

Full-project static checks and production build pass. HTTP checks verify both incidents, run-scoped diagnostics, impact, copied-state recovery, reset, input validation, ten registered operations, and real OSV serialization (five lodash advisories). The Investigator production binding is exercised with MockLLM and a simulated authentication failure. Browser verification covers the live incident controls; prior fixture browser checks cover panel error states and reset/selection races. Live Gemini output quality is **not verified** and remains a manual provider acceptance step; no credentials were read or quota consumed.

The acceptance checklist records implementation and deterministic verification, not deployment or live Gemini quality. Simulator state and tool recording are process-local; use a single server process for this implementation. Deployment and shared multi-worker persistence remain deferred as stated above.

## Parallel integration matrix

| Capability | Member 1 | Member 2 | Dashboard integration owner |
| --- | --- | --- | --- |
| Simulation | Implements and tests directly | Uses static evidence fixtures | Uses existing UI state fixtures |
| Diagnostics | Implements and tests directly | Uses matching evidence fixtures | Uses matching panel fixtures |
| OSV | No dependency | Implements and tests directly | Uses scan-result fixtures |
| Investigator | No dependency | Uses diagnostic fixtures and MockLLM | Uses investigation-result fixtures |
| Dashboard | No dependency | No dependency | Implements against frozen contracts |
| Public endpoints | Exports feature functions | Exports feature functions | Connects wrappers during integration |

No feature implementation depends on another member's branch. Only Dashboard integration owner's final adapter wiring consumes completed feature exports.

## Implementation sequence

### Hours 0–2: independent core work

- Member 1 builds simulation state, incidents, and diagnostics.
- Member 2 builds OSV transport/normalization and extracts the Investigator module.
- Dashboard integration owner builds complete UI state rendering against fixtures.

### Hours 2–4: independent verification

- Member 1 verifies propagation, reset, privacy, and diagnostic evidence.
- Member 2 verifies OSV success/error paths and MockLLM behavior.
- Dashboard integration owner verifies interactive panel states, graph updates, and stale-response handling with fixtures.

### Hour 4: first integration checkpoint

- Member 1 and Member 2 hand off typed exports and fixtures.
- Dashboard integration owner connects simulator, diagnostics, scanner, and Investigator wrappers.
- Feature owners continue impact, recovery, and error-hardening work while integration proceeds.

### Hours 4–6: end-to-end implementation

- Connect incidents to graph state.
- Connect diagnostic tools to the Investigator.
- Connect scanner results and security impact.
- Connect recovery preview.
- Fix contract and serialization issues without broadening scope.

### Hour 6: second integration checkpoint

- Verify both deterministic incidents.
- Verify real OSV success, empty, partial, and failure behavior.
- Verify evidence-backed hidden-edge discovery with MockLLM, then with Gemini if a valid key is available.

### Hours 6–8: implementation hardening

- Fix compile, runtime, state-reset, stale-response, and error-rendering defects.
- Run full Jac checks, feature tests, production client build, and HTTP operation checks.
- Remove dead fixtures only when equivalent live paths are verified.
- Leave optional unfinished functionality explicitly disabled rather than partially connected.

## Integration acceptance checklist

- [x] Jac project compiles, starts, and builds its production client bundle.
- [x] Six services and five initial documented dependencies render.
- [x] Both incidents produce the specified deterministic service states.
- [x] Diagnostic tools return run-scoped evidence without exposing private simulator state.
- [x] A real OSV request succeeds and all error classes remain distinguishable.
- [x] Investigator uses only allowed tools and cites evidence for discovered edges.
- [x] Reset clears all run-specific backend and frontend state.
- [x] Security impact uses cautious, evidence-based language.
- [x] Recovery preview does not mutate active simulation state.
- [x] Gemini and OSV failures are handled without crashing the application.
- [x] At least 80% of authored project code remains Jac.
- [x] No secrets or generated artifacts are tracked.

## Phase 2

The Security Analyst and Recovery agents are planned in [AGENTS_PLAN.md](AGENTS_PLAN.md). WP0 (shared contracts, operation names, gateway mapping, and baseline fixes) is applied on `main`; WP1 and WP2 build against those contracts in parallel.


### Dashboard and agent integration implementation

- [x] Keep the accepted WP0 records and operation names unchanged.
- [x] Add typed assessment/proposal presentation, advisory/evidence citations, model/deterministic labels, incomplete coverage, loading/empty/failed states and wrong-repair outcomes.
- [x] Keep the atomic dashboard architecture; reuse a deterministic comparison molecule.
- [x] Add explicit agent ports, a fresh session per request and copied read-only fact snapshots.
- [x] Chain the latest scan and completed evidence-backed investigation through a run-scoped repository.
- [x] Validate citations, deterministic dependent reach, supported actions and simulator verification.
- [x] Reject stale run, request, input and topology revisions, and clear stored/UI output on reset.
- [x] Keep deterministic/manual fallback available when a model operation fails.
- [x] Add MockLLM and concurrent-session tests with no paid model calls.
- [ ] Bind the actual Security Analyst and Recovery feature exports and action-aware simulator callbacks when those modules are handed off.
- [ ] Verify both incidents end-to-end with the actual new agents, then perform separately configured live-provider acceptance.

The two feature-owner agent directories are absent from this checkout. Production therefore uses explicit prerequisite/unavailable failures. [Agent integration](AGENT_INTEGRATION.md) documents the handoff protocol, test commands and Jac 0.34.19's narrow recovery model-schema requirement. Fixture and MockLLM verification do not mark the missing live agent acceptance complete.
