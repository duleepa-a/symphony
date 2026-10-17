"""Recovery preview computed on a copy of simulation state."""

import from contracts { OperationEnvelope, OperationError }
import from simulation.incidents {
    EFFECTIVE_REPAIRS,
    REPAIR_ACTIONS,
    propagate_failure
}
import from simulation.state {
    sim_state,
    current_states,
    service_dicts,
    is_known_service,
    unknown_service
}

def sim_preview_recovery(service_id: str) -> OperationEnvelope {
    if not is_known_service(service_id) {
        return unknown_service(service_id);
    }
    before = dict(current_states());
    root_fault = sim_state.root_fault;
    if root_fault == "" {
        return OperationEnvelope(
            status="completed",
            data={
                "service_id": service_id,
                "candidate_repair": "No repair needed: no incident is active.",
                "before": service_dicts(before),
                "after": service_dicts(before),
                "outcome": "no_incident"
            }
        );
    }
    # Computed on copies only; the active incident is never mutated.
    repaired_fault = "" if root_fault == service_id else root_fault;
    after = propagate_failure(repaired_fault);
    outcome = "recovered" if repaired_fault == "" else "not_recovered";
    return OperationEnvelope(
        status="completed",
        data={
            "service_id": service_id,
            "candidate_repair": f"Restart and restore {service_id}.",
            "before": service_dicts(before),
            "after": service_dicts(after),
            "outcome": outcome
        }
    );
}

def sim_list_repair_options -> OperationEnvelope {
    return OperationEnvelope(
        status="completed",
        data={
            "options": [
                {"action": action, "description": REPAIR_ACTIONS[action]}
                for action in REPAIR_ACTIONS
            ],
            "simulation_run_id": sim_state.simulation_run_id
        }
    );
}

def sim_preview_repair(service_id: str, action: str) -> OperationEnvelope {
    # Computed on copies only. The output never names the fault or which action fits it.
    if not is_known_service(service_id) {
        return unknown_service(service_id);
    }
    if action not in REPAIR_ACTIONS {
        return OperationEnvelope(
            status="failed",
            error=OperationError(
                code="unknown_repair_action",
                message=f"Unknown repair action '{action}'."
            )
        );
    }
    before = dict(current_states());
    outcome = "no_incident";
    after = before;
    if sim_state.root_fault != "" {
        works = service_id == sim_state.root_fault
        and action in EFFECTIVE_REPAIRS.get(sim_state.fault_kind, []);
        after = propagate_failure("" if works else sim_state.root_fault);
        outcome = "recovered" if works else "not_recovered";
    }
    return OperationEnvelope(
        status="completed",
        data={
            "service_id": service_id,
            "action": action,
            "candidate_repair": f"{action} {service_id}",
            "before": service_dicts(before),
            "after": service_dicts(after),
            "outcome": outcome,
            "simulation_run_id": sim_state.simulation_run_id
        }
    );
}
