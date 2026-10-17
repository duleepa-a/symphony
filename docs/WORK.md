# SYMPHONY Remaining Implementation Work

This plan starts after the initial foundation implementation. It covers product implementation only. Demo recording, submission preparation, repository promotion, and deployment are intentionally deferred.

## Foundation already available

Do not rebuild these items:

- Jac 0.37.25 `web-app` project, dependency lock, and development commands.
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
- `contracts.jac` is frozen. Members may propose additive fields, but Member 3 applies agreed shared-contract changes during integration.
- `operations.jac`, `main.jac`, `jac.toml`, and `jac.lock` are integration-owned by Member 3. Members 1 and 2 expose feature functions from their own modules and do not edit these shared files.
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
| `dashboard/`, `operations.jac`, `main.jac`, shared configuration | Member 3 | Read-only outside agreed integration changes |
| `contracts.jac` | Member 3 integrates | Members 1 and 2 propose additive changes |
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

- [ ] Implement an in-memory simulation state containing current incident, service states, discovered edges, and `simulation_run_id`.
- [ ] Keep the complete true graph private inside the simulation feature.
- [ ] Keep the public documented graph initially limited to the five existing dependencies.
- [ ] Implement `normal`, `auth_outage`, and `payment_outage` scenarios.
- [ ] Propagate failure from a failed dependency toward services that depend on it.
- [ ] Implement reset with healthy states, no discovered edges, and a new run ID.
- [ ] Expose feature functions for starting, reading, and resetting simulation state. Use feature-specific names so they do not collide with public wrappers in `operations.jac`.

### Diagnostic implementation

- [ ] Generate deterministic health observations for each service.
- [ ] Generate concise synthetic logs that expose symptoms without directly naming the hidden root fault.
- [ ] Generate request traces that can reveal Payment-to-Auth during the Auth outage.
- [ ] Return `Evidence` records carrying unique evidence IDs and the active `simulation_run_id`.
- [ ] Reject unknown service IDs explicitly.
- [ ] Ensure diagnostic output never serializes the true graph, private fault field, or internal propagation data.

### Graph impact and recovery

- [ ] Implement reverse dependency traversal using documented plus accepted discovered edges.
- [ ] Describe downstream services as potentially exposed or operationally affected.
- [ ] Implement recovery preview against a copied simulation state so preview does not mutate the active incident.
- [ ] Return before/after service states and a deterministic verification outcome.

### Independent verification

- [ ] Normal state: all six services healthy.
- [ ] Auth outage: Auth, Payment, API Gateway, and Frontend down; Catalog and Database healthy.
- [ ] Payment outage: Payment, API Gateway, and Frontend down; Auth, Catalog, and Database healthy.
- [ ] Auth traces support Payment depends on Auth without directly returning the true graph.
- [ ] Reset invalidates evidence from the previous run.
- [ ] Simulation tests run without dashboard, OSV, or Gemini access.

### Handoff to Member 3

- Export one function for each public wrapper Member 3 must connect.
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

- [ ] Read exact package inventories from `catalog.jac`; do not duplicate them.
- [ ] Implement server-side `POST https://api.osv.dev/v1/query` calls.
- [ ] Fetch `GET /v1/vulns/{id}` only when query results lack required display details.
- [ ] Normalize advisory ID, summary, available severity, reference URL, package, ecosystem, and version.
- [ ] Preserve missing severity as `unknown`.
- [ ] Add request timeout and malformed-response handling.
- [ ] Keep completed no-findings, partial failure, and complete failure states distinct.
- [ ] Ensure an API failure can never become a completed zero-findings response.
- [ ] Return one package-level result for every inventory item.

### Investigator implementation

- [ ] Move the existing `investigate_incident` declaration from `operations.jac` into `investigation/agent.jac` during this branch's work; Member 3 performs the shared-file integration.
- [ ] Keep Gemini as the configured provider and preserve the six-iteration limit.
- [ ] Develop against diagnostic fixtures matching the frozen `Evidence` contract.
- [ ] Give the model only documented topology, user-visible state, and diagnostic tools.
- [ ] Record actual tool calls in order.
- [ ] Return observed evidence, ranked candidates, discovered dependencies, and a concise explanation.
- [ ] Accept a discovered dependency only when referenced request-trace evidence supports it.
- [ ] Reject evidence whose `simulation_run_id` differs from the active run.
- [ ] Return `failed` for authentication, quota, timeout, malformed-output, and tool errors.

### Independent verification

- [ ] Verify at least one real OSV query against a known exact package version.
- [ ] Verify a completed no-findings fixture.
- [ ] Verify timeout, non-200, malformed, partial, and failed scan paths.
- [ ] Test the Investigator with `MockLLM`; tests must not consume Gemini quota.
- [ ] Verify unsupported model claims do not become discovered edges.
- [ ] Verify the feature modules run without the dashboard or Member 1's branch.

### Handoff to Member 3

- Export scanner and Investigator functions with documented typed returns.
- Provide scanner fixtures for completed findings, completed no findings, partial, and failed states.
- Provide Investigator fixtures for completed, failed, and stale-evidence states.
- Do not modify `operations.jac`, dashboard components, or shared configuration during the handoff.

## Member 3 — Dashboard behavior and integration

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

- [ ] Replace the single generic operation message with panel-specific state.
- [ ] Render loading, completed, empty, partial, failed, and not-implemented states for each operation.
- [ ] Connect incident selection, trigger, and reset to live wrappers when Member 1 is integrated.
- [ ] Update graph node states after incident operations.
- [ ] Render investigation tool timeline, evidence, candidates, explanation, and discovered edges.
- [ ] Visually distinguish documented edges from evidence-backed discovered edges.
- [ ] Render package-level OSV results with advisory links and `unknown` severity where needed.
- [ ] Add a security-impact section that avoids unsupported vulnerable/compromised wording.
- [ ] Render recovery before/after state and verification outcome.
- [ ] Ignore stale asynchronous responses after the simulation run changes.
- [ ] Preserve responsive layout, keyboard focus, and reduced-motion behavior.

### Integration ownership

- [ ] Import Member 1's feature functions and connect the public simulation/diagnostic wrappers in `operations.jac`.
- [ ] Import Member 2's feature functions and connect scanner/Investigator wrappers.
- [ ] Move the current inline Investigator code out of `operations.jac` after Member 2's module is available.
- [ ] Apply only agreed additive contract changes.
- [ ] Keep public operation names and response envelopes stable.
- [ ] Resolve integration conflicts in shared files rather than asking feature branches to edit them.

### Application verification

- [ ] Run full-project `jac check --nowarn` and formatting checks.
- [ ] Build the production client bundle.
- [ ] Start the application and verify every public operation over HTTP.
- [ ] Verify all six nodes and exactly five initial documented edges.
- [ ] Verify hidden relationships are absent before evidence-backed discovery.
- [ ] Verify reset clears incident, investigation, impact, recovery, and discovered-edge UI state.
- [ ] Verify provider and OSV failures remain visible and truthful.
- [ ] Update README architecture and run instructions to match the integrated implementation.

## Parallel integration matrix

| Capability | Member 1 | Member 2 | Member 3 |
| --- | --- | --- | --- |
| Simulation | Implements and tests directly | Uses static evidence fixtures | Uses existing UI state fixtures |
| Diagnostics | Implements and tests directly | Uses matching evidence fixtures | Uses matching panel fixtures |
| OSV | No dependency | Implements and tests directly | Uses scan-result fixtures |
| Investigator | No dependency | Uses diagnostic fixtures and MockLLM | Uses investigation-result fixtures |
| Dashboard | No dependency | No dependency | Implements against frozen contracts |
| Public endpoints | Exports feature functions | Exports feature functions | Connects wrappers during integration |

No feature implementation depends on another member's branch. Only Member 3's final adapter wiring consumes completed feature exports.

## Implementation sequence

### Hours 0–2: independent core work

- Member 1 builds simulation state, incidents, and diagnostics.
- Member 2 builds OSV transport/normalization and extracts the Investigator module.
- Member 3 builds complete UI state rendering against fixtures.

### Hours 2–4: independent verification

- Member 1 verifies propagation, reset, privacy, and diagnostic evidence.
- Member 2 verifies OSV success/error paths and MockLLM behavior.
- Member 3 verifies interactive panel states, graph updates, and stale-response handling with fixtures.

### Hour 4: first integration checkpoint

- Member 1 and Member 2 hand off typed exports and fixtures.
- Member 3 connects simulator, diagnostics, scanner, and Investigator wrappers.
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

- [ ] Jac project compiles, starts, and builds its production client bundle.
- [ ] Six services and five initial documented dependencies render.
- [ ] Both incidents produce the specified deterministic service states.
- [ ] Diagnostic tools return run-scoped evidence without exposing private simulator state.
- [ ] A real OSV request succeeds and all error classes remain distinguishable.
- [ ] Investigator uses only allowed tools and cites evidence for discovered edges.
- [ ] Reset clears all run-specific backend and frontend state.
- [ ] Security impact uses cautious, evidence-based language.
- [ ] Recovery preview does not mutate active simulation state.
- [ ] Gemini and OSV failures are handled without crashing the application.
- [ ] At least 80% of authored project code remains Jac.
- [ ] No secrets or generated artifacts are tracked.
