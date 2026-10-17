"""Static Recovery agent results for dashboard and integration work. Not production data."""

import from contracts { OperationEnvelope }
import from agent_support.models { agent_failure }

glob FIXTURE_RUN = "fixture-run";

def fixture_investigation(incident_id: str) -> dict[str, any] {
    origin = "auth" if incident_id == "auth_outage" else "payment";
    return {
        "simulation_run_id": FIXTURE_RUN,
        "candidate_root_causes": [f"{origin} failure"],
        "discovered_dependencies": [],
        "explanation": f"Fixture investigation pointing at {origin}.",
        "evidence": [
            {
                "id": f"{FIXTURE_RUN}-ev-1",
                "tool": "check_service_health",
                "service_id": origin,
                "observation": {"state": "down"},
                "simulation_run_id": FIXTURE_RUN,

            }
        ],

    };
}

def _states(state: str) -> list[dict[str, str]] {
    return [
        {"id": "auth", "name": "Auth", "state": state},
        {"id": "payment", "name": "Payment", "state": state},

    ];
}

def fixture_recovery_completed -> OperationEnvelope {
    return OperationEnvelope(
        status="completed",
        data={
            "simulation_run_id": FIXTURE_RUN,
            "target_service_id": "auth",
            "action": "restart",
            "rationale": "Auth is down and Payment depends on it; restart was previewed as recovered.",
            "cited_evidence_ids": [f"{FIXTURE_RUN}-ev-1"],
            "preview": {
                "before": _states("down"),
                "after": _states("healthy"),
                "outcome": "recovered",

            },
            "tool_timeline": [
                "get_investigation_result()",
                "list_repair_options()",
                "preview_repair(auth, restart)",

            ],

        },
    );
}

def fixture_recovery_not_recovered -> OperationEnvelope {
    result = fixture_recovery_completed();
    result.data["action"] = "failover";
    result.data["preview"] = {
        "before": _states("down"),
        "after": _states("down"),
        "outcome": "not_recovered",

    };
    return result;
}

def fixture_recovery_failed -> OperationEnvelope {
    return agent_failure(
        "recovery_agent_authentication_error", "The model credential was rejected."
    );
}
