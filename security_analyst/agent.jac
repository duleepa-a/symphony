"""Bounded Security Analyst: explains and prioritizes OSV findings over rule-based facts."""

import json;
import from threading { RLock }
import from contracts { OperationEnvelope }
import from agent_support.models {
    agent_failure,
    envelope_for_model_error,
    make_agent_model
}
import from simulation.impact { sim_analyze_impact }
import from simulation.state { sim_is_current_run }
import from .tools {
    SecurityJudgment,
    advisories_in,
    begin_security_session,
    get_impact_tool,
    get_known_dependencies_tool,
    get_scan_results_tool,
    security_tool_timeline,
}
import from .validation {
    assessment_to_dict,
    build_assessment,
    deterministic_assessment,
    validate_judgment,
}

glob analyst_model = make_agent_model();
glob analyst_lock = RLock();

def judge_security_impl(incident_context: str, active_run_id: str,) -> SecurityJudgment by analyst_model(
    tools=[get_scan_results_tool, get_impact_tool, get_known_dependencies_tool],
    temperature=0.2,
    max_tokens=900,
    max_react_iterations=6,
    max_output_retries=1,
);

sem judge_security_impl = "Assess the security risk of one scanned service. Read the scan results and the graph impact first. Report only advisories that appear in the scan, cite their IDs, and never call a dependent service vulnerable or compromised without direct evidence.";
sem judge_security_impl.incident_context = "The scanned service ID, scan status, and run ID.";
sem judge_security_impl.active_run_id = "The current simulation run ID.";

def _context(service_id: str, scan_status: str) -> str {
    return json.dumps({"service_id": service_id, "scan_status": scan_status});
}

def run_security_analysis_with(
    judge: Callable[[str, str], SecurityJudgment],
    service_id: str,
    scan: OperationEnvelope,
    run_id: str,
) -> OperationEnvelope {
    if not sim_is_current_run(run_id) {
        return agent_failure("stale_run", "The simulation changed. Run it again.");
    }
    scan_status = scan.status;
    if scan_status not in ["completed", "partial"] or not scan.data {
        return agent_failure(
            "scan_unavailable",
            "No usable scan exists. Run the vulnerability scan first; a failed scan is not a clean result."
        );
    }
    data = scan.data;
    if data.get("service_id", service_id) != service_id {
        return agent_failure(
            "scan_service_mismatch", "The scan belongs to a different service."
        );
    }
    if data.get("simulation_run_id", run_id) != run_id {
        return agent_failure(
            "stale_scan", "The scan belongs to a different simulation run."
        );
    }
    impact = sim_analyze_impact(service_id);
    if impact.status != "completed" {
        return impact;
    }
    dependents = impact.data["dependent_services"];
    rule_based = impact.data["priority"];
    advisories = advisories_in(data);
    if len(advisories) == 0 {
        explanation = (
            "OSV reported no advisories for the scanned inventory. This covers only the listed packages."
                if scan_status == "completed"
                else "The scan was incomplete and reported no advisories. This is not an all-clear: some lookups failed."
        );
        assessment = deterministic_assessment(
            data, service_id, run_id, dependents, rule_based, explanation
        );
        return OperationEnvelope(
            status=scan_status, data=assessment_to_dict(assessment, scan_status, 0, []),
        );
    }
    with analyst_lock {
        begin_security_session(run_id, service_id, data);
        try {
            judgment = judge(_context(service_id, scan_status), run_id);
            if not sim_is_current_run(run_id) {
                return agent_failure(
                    "stale_run", "The simulation changed during the security analysis."
                );
            }
            problem = validate_judgment(judgment, data);
            if problem is not None {
                return agent_failure(problem.code, problem.message);
            }
            assessment = build_assessment(
                judgment, data, service_id, run_id, dependents, rule_based
            );
            return OperationEnvelope(
                status=scan_status,
                data=assessment_to_dict(
                    assessment, scan_status, len(advisories), security_tool_timeline()
                ),
            );
        } except Exception as error {
            return envelope_for_model_error("security_analyst", error);
        }
    }
}

def run_security_analysis_impl(
    service_id: str, scan: OperationEnvelope, run_id: str
) -> OperationEnvelope {
    return run_security_analysis_with(judge_security_impl, service_id, scan, run_id);
}
