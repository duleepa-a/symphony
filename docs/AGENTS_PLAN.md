# SYMPHONY Phase 2: Security Analyst and Recovery Agents

Team: two active members. Member 1 owns the simulator and both agent modules. Member 3 owns integration and the dashboard. Member 2 is not assigned in this phase.

This plan starts after the dashboard integration on `main` (PR #1). It adds two agents beside the existing Investigator. Each agent reasons over deterministic facts, and a rule-based component verifies or bounds its output.

## Baseline on main

- All nine public operations bind to real features through `integration/` (gateway, ports, bindings, adapters).
- The Investigator (`investigation/agent.jac`) is the only byLLM agent. It uses Gemini with a fallback model, six ReAct iterations, three diagnostic tools, and evidence validation.
- Security impact (`simulation/impact.jac`) is rule-based and graph-only. It does not read OSV findings.
- Recovery preview (`simulation/recovery.jac`) works on a copied state. It has one fixed repair, "Restart and restore X".
- `jac check . --nowarn` passes (56 files, verified in WSL, Jac 0.34.19).

## Agent overview

| Agent | Reads | Produces | Bounded or verified by |
| --- | --- | --- | --- |
| Investigator (exists) | health, logs, traces | evidence, ranked causes, discovered edges | evidence IDs, run ID, trace-backed edges |
| Security Analyst (new) | OSV scan results, rule-based impact, known graph | per-finding risk assessment and priority | advisory IDs from the current scan, rule-based priority as fallback |
| Recovery (new) | Investigator result, impact, repair options | repair proposal and explanation | the copied-state preview returns `recovered` or `not_recovered` |

Rule-based impact and OSV code stays as the fact layer. The agents explain and prioritize; they do not replace it.

## Constraint: do not reuse the Investigator's recorder

`investigation/tools.jac` keeps tool calls and evidence in process-wide lists, and `integration/investigation_adapter.sv.jac` serializes sessions with a lock to protect them. New agents must keep their own run-scoped record (a record object created per session and passed to its tools), so concurrent sessions cannot mix evidence. The Investigator is left as it is.

## Shared rules for every agent

- Bounded `max_react_iterations`, read-only tools, no access to `root_fault` or the true graph.
- Every claim cites evidence: a diagnostic evidence ID or a current-scan advisory ID. Unsupported claims are rejected, not trimmed.
- Any provider, tool or validation error returns `failed` with a specific error code. Never fake success.
- Output is stamped with `simulation_run_id`. Reset clears it. The gateway drops results from a stale run.
- Tests use `MockLLM` and consume no Gemini quota.
- Dashboard labels model-generated output and deterministic output differently.

## Work packages

### WP0: Contract and plan changes (Member 3, done)

- Add the additive records `SecurityAssessment` and `RecoveryProposal` to `contracts.jac`, and freeze them before WP1 and WP2 start.
- Add the public operations `run_security_analysis(service_id)` and `run_recovery_agent()` to `operations.jac`, using the same `OperationEnvelope`.
- Fix `impact()` in `integration/bindings.sv.jac`, which joins `potential_exposure` into one string while the simulator returns a list. Keep the list for agent consumers, or format it only in the dashboard.
- Replace the Mac path and add WSL instructions in `docs/SETUP.md`.
- Mark this plan as accepted in `docs/WORK.md`.

Proposed shapes (additive; final fields are agreed at WP0):

```text
SecurityAssessment = {
  "service_id": string,
  "simulation_run_id": string,
  "findings": [{ "advisory_id": string, "package": string, "risk": string,
                 "cited_advisory_ids": [string] }],
  "dependents": [string],
  "priority": "low | medium | high",
  "rule_based_priority": "low | medium | high",
  "explanation": string
}

RecoveryProposal = {
  "simulation_run_id": string,
  "target_service_id": string,
  "action": string,                 # one of the listed repair actions
  "rationale": string,
  "cited_evidence_ids": [string],
  "preview": { "before": [...], "after": [...], "outcome": "recovered | not_recovered | no_incident" }
}
```

### WP1: Security Analyst (Member 1)

Folder `security_analyst/` (own tests and fixtures).

- Tools (read-only): `get_scan_results(service_id)`, `get_impact(service_id)`, `get_known_dependencies()`.
- Inputs: the output of `scan_service_dependencies` and `sim_analyze_impact`.
- Validation: every finding must cite an advisory ID present in the current scan. Reject "vulnerable" or "compromised" wording for dependents. If the model's priority is lower than the rule-based priority, return both and flag it.
- Failed or partial scans: the analyst must not produce an "all clear". It reports the scan as incomplete.
- Fallback: on any agent failure, the existing rule-based impact is still shown.
- Tests: MockLLM happy path, invented advisory ID rejected, failed scan, partial scan, no findings, unknown service, stale run.

### WP2: Recovery agent (Member 1)

Folder `recovery_agent/` (own tests and fixtures), plus a small simulator change.

- Simulator: extend `simulation/recovery.jac` with repair actions (at least `restart`, `rollback`, `failover`), each with a deterministic effect. A wrong target or a wrong action returns `not_recovered`. Keep `sim_preview_recovery(service_id)` working for the existing panel.
- Tools (read-only): `list_repair_options()`, `get_investigation_result()`, `get_impact(service_id)`, `preview_recovery(service_id, action)`. The preview works on a copy and must not reveal `root_fault` in its output.
- Validation: the proposal must cite evidence IDs from the current Investigator result, and its `action` must be in the listed options. The final outcome comes from the preview, never from the model.
- Tests: MockLLM picks the right service for `auth_outage` and `payment_outage`, wrong pick reported as `not_recovered`, no active incident, no Investigator result yet, stale run, preview does not mutate the active incident.

### WP3: Integration (Member 3)

- Bind both agents through `integration/` (new adapters, one session each, run-ID checks before and after).
- Chain the data: Security Analyst takes the latest scan; Recovery takes the latest Investigator result. If a prerequisite is missing, return a clear `failed` code such as `investigation_required` or `scan_required`.
- Reset clears stored agent results.

### WP4: Dashboard (Member 3)

- Security panel: show the analyst's assessment beside the rule-based priority.
- Recovery panel: show the proposal, the before/after preview, and the verification outcome.
- Label model output and deterministic output differently. Show loading, empty and failed states. Ignore stale responses with the existing request guard.

## Ownership and parallel work

| Member | Packages | Files |
| --- | --- | --- |
| Member 1 | WP2 Recovery agent, then WP1 Security Analyst | `simulation/` (repair actions), `recovery_agent/`, `security_analyst/` |
| Member 3 | WP4 Dashboard, then WP3 Integration | `dashboard/`, `integration/`, `operations.jac`, `contracts.jac`, `main.jac`, shared config |

Member 1 does not edit `operations.jac`, `contracts.jac`, `integration/` or `dashboard/`. Additive contract changes are proposed to Member 3 and agreed at the checkpoint.

Parallel from the start (WP0 contracts are frozen):

- Member 1 builds WP2, then WP1, each against its own fixtures and `MockLLM`. Neither needs the dashboard, the integration layer, or the other agent. Each keeps its own run-scoped record.
- Member 3 builds WP4 against fixture envelopes in the agreed shapes, and drafts the WP3 adapters against the agreed function signatures.

Must wait:

- WP3 can only be tested with the real agents after Member 1 exports them.
- Any new contract field needed by an agent is raised at the checkpoint, not mid-build, because WP4 depends on the shapes.

## Order and timing (about 6 hours)

| Hours | Member 1 | Member 3 |
| --- | --- | --- |
| 0-3 | WP2: repair actions, Recovery agent, tests | WP4: Recovery and Security panels on fixtures; draft WP3 adapters |
| 3 | Checkpoint: hand off WP2 exports, fixtures, and function signatures | Agree any contract changes |
| 3-5 | WP1: Security Analyst, tests | WP3 (Recovery): bind, chain, reset; end-to-end check |
| 5-6 | Hand off WP1 exports | WP3 (Security): bind and chain; joint end-to-end check on both incidents; live Gemini run |

If time runs short: finish WP2 and the Recovery side of WP3 and WP4, and keep the Security Analyst rule-based. The rule-based impact and priority remain in the app either way.

## Acceptance checklist

- [ ] `jac check . --nowarn` and all test suites pass (serial: `JAC_TEST_JOBS=0`).
- [ ] Both incidents run through Investigator, Recovery and Security Analyst, and every claim cites evidence or an advisory ID.
- [ ] A failed or partial OSV scan never produces a clean assessment.
- [ ] Recovery preview does not change the active incident, and a wrong pick shows `not_recovered`.
- [ ] No agent tool exposes the root fault or the true graph.
- [ ] Reset clears all agent output, and stale results are dropped.
- [ ] Gemini and OSV failures show a visible failed state without crashing the app.
- [ ] Tests use `MockLLM` and spend no Gemini quota.
- [ ] No secrets or generated artifacts are tracked.
