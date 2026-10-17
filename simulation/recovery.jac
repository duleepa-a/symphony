"""Recovery preview computed on a copy of simulation state."""

import from contracts { OperationEnvelope }
import from simulation.incidents { propagate_failure }
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
