"""Run-scoped, read-only tool boundary for the Recovery agent.

This module keeps its own session record and never touches the Investigator's
recorder. Tools expose repair options, the current Investigator result, graph
impact, and a non-mutating repair preview. None of them returns the injected
fault or the private graph.
"""

import from catalog { initial_services }
import from simulation.impact { sim_analyze_impact }
import from simulation.recovery { sim_list_repair_options, sim_preview_repair }
import from simulation.state { sim_is_current_run }

obj RecoveryChoice {
    has target_service_id: str,
        action: str,
        rationale: str,
        cited_evidence_ids: list[str] = [];
}

sem RecoveryChoice = "The repair the agent proposes: one service and one listed action, with the evidence that supports it.";
sem RecoveryChoice.target_service_id = "Stable service ID to repair: frontend, api_gateway, payment, catalog, auth, or database.";
sem RecoveryChoice.action = "Exactly one action returned by list_repair_options.";
sem RecoveryChoice.rationale = "Concise reason for the target and action. State uncertainty. Do not claim a repair works unless a preview showed recovered.";
sem RecoveryChoice.cited_evidence_ids = "Evidence IDs from get_investigation_result that support the chosen target.";

obj RecoverySession {
    has run_id: str = "",
        investigation: dict[str, any] = {},
        tool_timeline: list[str] = [];
}

glob session: RecoverySession = RecoverySession();

def begin_recovery_session(run_id: str, investigation: dict[str, any]) {
    session.run_id = run_id;
    session.investigation = investigation;
    session.tool_timeline = [];
}

def recovery_tool_timeline -> list[str] {
    return session.tool_timeline.copy();
}

def _record(label: str) {
    if not sim_is_current_run(session.run_id) {
        raise RuntimeError("Simulation changed during recovery analysis.");
    }
    session.tool_timeline.append(label);
}

def _tool_error(code: str, message: str) -> dict[str, any] {
    return {"error": {"code": code, "message": message}};
}

def list_repair_options_tool -> dict[str, any] {
    _record("list_repair_options()");
    return {"options": sim_list_repair_options().data["options"]};
}

sem list_repair_options_tool = "List every repair action available. The list does not say which action fits which service or fault.";

def get_investigation_result_tool -> dict[str, any] {
    _record("get_investigation_result()");
    investigation = session.investigation;
    return {
        "candidate_root_causes": investigation.get("candidate_root_causes", []),
        "discovered_dependencies": investigation.get("discovered_dependencies", []),
        "explanation": investigation.get("explanation", ""),
        "evidence": [
            {
                "id": item.get("id", ""),
                "tool": item.get("tool", ""),
                "service_id": item.get("service_id", ""),
                "observation": item.get("observation", {}),

            } for item in investigation.get("evidence", [])
        ],

    };
}

sem get_investigation_result_tool = "Read the Investigator's result for the active incident: ranked candidate causes, discovered dependencies, explanation, and the evidence records you may cite by ID.";

def get_impact_tool(service_id: str) -> dict[str, any] {
    _record(f"get_impact({service_id})");
    result = sim_analyze_impact(service_id);
    if result.status != "completed" {
        return _tool_error(result.error.code, result.error.message);
    }
    return {
        "service_id": service_id,
        "dependent_services": result.data["dependent_services"],
        "priority": result.data["priority"],

    };
}

sem get_impact_tool = "Show which services depend on one service through known dependencies. Use it to judge blast radius, not to find the cause.";
sem get_impact_tool.service_id = "Stable service ID to inspect.";

def preview_repair_tool(service_id: str, action: str) -> dict[str, any] {
    _record(f"preview_repair({service_id}, {action})");
    result = sim_preview_repair(service_id, action);
    if result.status != "completed" {
        return _tool_error(result.error.code, result.error.message);
    }
    return {
        "service_id": service_id,
        "action": action,
        "outcome": result.data["outcome"],
        "after": result.data["after"],

    };
}

sem preview_repair_tool = "Preview one repair on a copy of the simulation. It never changes the active incident. The outcome is recovered, not_recovered, or no_incident.";
sem preview_repair_tool.service_id = "Stable service ID to repair.";
sem preview_repair_tool.action = "One action returned by list_repair_options.";

def known_service_ids -> list[str] {
    return [service.id for service in initial_services()];
}
