"""Deterministic diagnostics derived from simulation state.

Output exposes symptoms only: never the injected root fault, the full true
graph, or propagation internals. Request traces list only the calls observed
for one service, which is how hidden dependencies can be discovered.
"""

import from contracts { Evidence, OperationEnvelope }
import from simulation.incidents { true_dependencies }
import from simulation.state {
    sim_state,
    current_states,
    is_known_service,
    unknown_service
}

glob BASELINE_LATENCY_MS: dict[str, int] = {
         "frontend": 35,
         "api_gateway": 22,
         "payment": 48,
         "catalog": 31,
         "auth": 18,
         "database": 12
     };

def issue_evidence(
    tool: str, service_id: str, observation: dict[str, any]
) -> OperationEnvelope {
    sim_state.evidence_counter += 1;
    evidence = Evidence(
        id=f"{sim_state.simulation_run_id}-ev-{sim_state.evidence_counter}",
        tool=tool,
        service_id=service_id,
        observation=observation,
        simulation_run_id=sim_state.simulation_run_id
    );
    sim_state.evidence_log[evidence.id] = evidence;
    return OperationEnvelope(
        status="completed",
        data={
            "id": evidence.id,
            "tool": evidence.tool,
            "service_id": evidence.service_id,
            "observation": evidence.observation,
            "simulation_run_id": evidence.simulation_run_id
        }
    );
}

def sim_check_health(service_id: str) -> OperationEnvelope {
    if not is_known_service(service_id) {
        return unknown_service(service_id);
    }
    down = current_states()[service_id] == "down";
    observation: dict[str, any] = {
        "state": "down" if down else "healthy",
        "http_status": 503 if down else 200,
        "error_rate_pct": 100 if down else 0,
        "latency_ms": None if down else BASELINE_LATENCY_MS[service_id]
    };
    return issue_evidence("check_service_health", service_id, observation);
}

def sim_get_logs(service_id: str) -> OperationEnvelope {
    if not is_known_service(service_id) {
        return unknown_service(service_id);
    }
    down = current_states()[service_id] == "down";
    entries: list[dict[str, str]] = [];
    if not down {
        entries.append({"level": "INFO", "message": "Request handled successfully."});
        entries.append({"level": "INFO", "message": "Health probe passed."});
    } elif sim_state.root_fault == service_id {
        entries.append(
            {
                "level": "ERROR",
                "message": "Service stopped responding to health probes."
            }
        );
        entries.append(
            {"level": "ERROR", "message": "Incoming requests rejected with status 503."}
        );
    } else {
        entries.append({"level": "WARN", "message": "Downstream request timed out."});
        entries.append(
            {
                "level": "ERROR",
                "message": "Request failed with status 503 after retries."
            }
        );
    }
    return issue_evidence("get_service_logs", service_id, {"entries": entries});
}

def sim_trace_requests(service_id: str) -> OperationEnvelope {
    if not is_known_service(service_id) {
        return unknown_service(service_id);
    }
    states = current_states();
    self_down = states[service_id] == "down";
    self_is_fault = sim_state.root_fault == service_id;
    spans: list[dict[str, str]] = [];
    for link in true_dependencies() {
        if link.source_id == service_id {
            outcome = "ok";
            if self_is_fault {
                outcome = "not_attempted";
            } elif states[link.target_id] == "down" {
                outcome = "timeout";
            }
            spans.append(
                {"direction": "outgoing", "peer": link.target_id, "outcome": outcome}
            );
        } elif link.target_id == service_id {
            spans.append(
                {
                    "direction": "incoming",
                    "peer": link.source_id,
                    "outcome": "error_503" if self_down else "ok"
                }
            );
        }
    }
    return issue_evidence("trace_requests", service_id, {"spans": spans});
}
