# Agents handoff (Member 1 -> Member 3)

Branch: `feat/agents-member1`. No shared files (`operations.jac`, `contracts.jac`, `main.jac`, `integration/`, `dashboard/`) were modified. Everything below is new or lives in `simulation/`.

All functions return `OperationEnvelope` (`status`, `data`, `error`). Failures use `status="failed"` with a specific `error.code`; nothing returns fake success. No test calls Gemini or OSV.

## Wiring table

| Public wrapper (WP0, `operations.jac`) | Feature function | Import from |
| --- | --- | --- |
| `run_recovery_agent()` | `run_recovery_agent_impl(investigation: dict, run_id: str)` | `recovery_agent.agent` |
| `run_security_analysis(service_id)` | `run_security_analysis_impl(service_id: str, scan: OperationEnvelope, run_id: str)` | `security_analyst.agent` |

Both take their prerequisite as an argument, so the adapter (WP3) decides where it comes from:

- **Recovery** needs the latest Investigator result for the current run. Pass `OperationEnvelope.data` from `run_investigation`; it must contain `simulation_run_id` and `evidence` (the investigation adapter already adds both). If none exists yet, return `investigation_required` yourself or pass `{}` and the agent returns it.
- **Security Analyst** needs the latest scan for that service. Pass the scan `OperationEnvelope` from `scan_service_dependencies`. If none exists, the agent returns `scan_unavailable`.
- `run_id` is `read_dashboard().simulation_run_id` at the start of the request. Both agents re-check it and return `stale_run` if the simulation changed.

Suggested adapter pattern: keep the latest investigation result and the latest scan per service in the integration layer, clear them on `start_incident` and `reset_incident`, and call the `_impl` functions under `simulation_lock`-compatible ordering (feature sessions use ContextVar isolation; model calls do not hold the simulator lock).

## Result shapes (`data` when `completed` or `partial`)

Recovery proposal (matches `RecoveryProposal`, plus `tool_timeline`):

```text
simulation_run_id, target_service_id, action, rationale, cited_evidence_ids,
preview: { before: [{id,name,state}], after: [{id,name,state}], outcome: recovered | not_recovered | no_incident },
tool_timeline: [string]
```

The gateway's required fields (`target_service_id`, `action`, `cited_evidence_ids`, `preview`) are all present. `status` is `completed` even when `preview.outcome` is `not_recovered`: the agent produced a proposal and the simulator verified it did not work.

Security assessment (matches `SecurityAssessment`, plus scan fields):

```text
service_id, simulation_run_id,
findings: [{ advisory_id, package, risk, cited_advisory_ids }],
dependents: [service_id], priority, rule_based_priority, explanation,
scan_status: completed | partial, finding_count, tool_timeline, analysis_source: model | deterministic
```

`status` mirrors the scan: `completed` for a completed scan, `partial` for a partial scan. A failed or missing scan returns `failed` / `scan_unavailable`, never an assessment.

## Error codes

| Agent | Code | Meaning |
| --- | --- | --- |
| both | `stale_run` | Simulation changed before or during the call |
| both | `recovery_agent_*` / `security_analyst_*` | `authentication_error`, `rate_limit`, `model_not_found`, `malformed_output`, `configuration_error`, `timeout`, `tool_or_provider_error` |
| Recovery | `investigation_required`, `stale_investigation`, `no_active_incident` | Missing or old prerequisite, or nothing to recover |
| Recovery | `unknown_service`, `unknown_repair_action`, `missing_citation`, `unsupported_citation`, `missing_rationale` | Choice failed validation |
| Security | `scan_unavailable`, `scan_service_mismatch`, `stale_scan` | Scan missing, failed, for another service, or from another run |
| Security | `unsupported_advisory`, `package_mismatch`, `missing_citation`, `invalid_priority`, `overstated_impact`, `missing_explanation`, `missing_risk` | Judgment failed validation |

## Behavior notes

- **Outcomes come from rules, not the model.** The Recovery preview and the Security `dependents` / `rule_based_priority` are computed by the simulator. The model supplies the target, action, rationale, risk wording, and priority.
- **Security with nothing to judge makes no model call.** A completed scan with no advisories returns a deterministic assessment. A partial scan with no advisories returns `partial` and says it is not an all-clear.
- **Skipped advisories are still reported.** If the model leaves out a scanned advisory, it appears with a plain "Not assessed by the model" risk line.
- **Lower model priority is flagged,** not hidden: both priorities are returned and a note is appended to the explanation.
- **Impact wording:** a sentence that says "compromised", "breached", "exploited", or "hacked" is rejected unless that particular claim explicitly negates it ("no direct evidence..."). A separate affirmative clause is still rejected.
- **Private state:** tools and previews never return `root_fault`, `fault_kind`, or the true graph. A test asserts this.
- **Session state:** each agent keeps its own run-scoped record in its own module. Neither touches the Investigator's recorder. Each invocation creates a copied ContextVar record and resets its token in finally, including failures. Concurrent calls do not share a recorder. Tool failures remain recorded even if a chooser catches the exception.
- **Models:** both use the shared pool in `agent_support/models.jac` (same Gemini env vars and fallback as the Investigator, 6 iterations, 45 s timeout).

## Simulator additions (`simulation/`)

- `incidents.jac`: private `INCIDENT_FAULT_KINDS` and `EFFECTIVE_REPAIRS`; public `REPAIR_ACTIONS` (`restart`, `rollback`, `failover`).
- `recovery.jac`: `sim_list_repair_options()` and `sim_preview_repair(service_id, action)` (copied state, never mutates the incident). In `auth_outage` only `restart` on `auth` recovers; in `payment_outage` only `rollback` on `payment` recovers. `failover` and wrong targets return `not_recovered`.
- The existing `sim_preview_recovery(service_id)` and `preview_recovery` are unchanged.
- `state.jac`: `SimState.fault_kind` (private).

## Fixtures

- `recovery_agent/fixtures.jac`: `fixture_investigation(incident_id)`, `fixture_recovery_completed()`, `fixture_recovery_not_recovered()`, `fixture_recovery_failed()`. Run ID is `"fixture-run"`.
- `security_analyst/fixtures.jac`: `fixture_scan(case)` for `findings`, `none`, `partial`, `failed`; `fixture_assessment_completed()`, `fixture_assessment_failed()`.

## Verifying

```bash
jac check . --nowarn
jac fmt . --check
export JAC_TEST_JOBS=0
jac test simulation/recovery.jac
jac test recovery_agent/agent.jac
jac test security_analyst/agent.jac
```

Live Gemini behavior for both agents is unverified; tests use `MockLLM` and fixed choosers.
