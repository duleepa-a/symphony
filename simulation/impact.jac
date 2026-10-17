"""Graph impact over documented plus accepted discovered dependencies only."""

import from contracts { OperationEnvelope }
import from simulation.state {
    known_dependencies,
    dependency_dict,
    is_known_service,
    unknown_service
}

def dependents_of(service_id: str) -> list[str] {
    # Reverse traversal: everything that directly or transitively depends on service_id.
    links = known_dependencies();
    found: list[str] = [];
    queue: list[str] = [service_id];
    while len(queue) > 0 {
        current = queue.pop(0);
        for link in links {
            if link.target_id == current and link.source_id not in found {
                found.append(link.source_id);
                queue.append(link.source_id);
            }
        }
    }
    return found;
}

def sim_analyze_impact(service_id: str) -> OperationEnvelope {
    if not is_known_service(service_id) {
        return unknown_service(service_id);
    }
    dependents = dependents_of(service_id);
    relationships = [
        dependency_dict(link)
        for link in known_dependencies()
        if link.target_id == service_id or link.target_id in dependents
    ];
    exposure = [
        f"{dependent} may be operationally affected through its dependency chain; there is no direct evidence it is vulnerable or compromised."
        for dependent in dependents
    ];
    priority = "low";
    if len(dependents) >= 3 {
        priority = "high";
    } elif len(dependents) >= 1 {
        priority = "medium";
    }
    return OperationEnvelope(
        status="completed",
        data={
            "service_id": service_id,
            "dependent_services": dependents,
            "relationships": relationships,
            "potential_exposure": exposure,
            "priority": priority
        }
    );
}
