"""Incident definitions and failure propagation over the private true graph."""

import from contracts { Dependency }
import from catalog { initial_services, documented_dependencies }

glob INCIDENT_ROOT_FAULTS: dict[str, str] = {
         "normal": "",
         "auth_outage": "auth",
         "payment_outage": "payment"
     };

# Private: the kind of fault behind each incident. It decides which repair works
# and is never serialized by diagnostics, previews, or agents.
glob INCIDENT_FAULT_KINDS: dict[str, str] = {
         "normal": "",
         "auth_outage": "crashed_process",
         "payment_outage": "bad_release"
     };

# Public repair catalog. Descriptions never say which repair fits which fault.
glob REPAIR_ACTIONS: dict[str, str] = {
         "restart": "Restart the service process.",
         "rollback": "Roll the service back to its previous release.",
         "failover": "Shift traffic to a standby replica of the service."
     };

# Private: repairs that clear each fault kind. Failover clears neither incident.
glob EFFECTIVE_REPAIRS: dict[str, list[str]] = {
         "crashed_process": ["restart"],
         "bad_release": ["rollback"]
     };

def true_dependencies -> list[Dependency] {
    # Private: documented links plus the hidden Payment -> Auth dependency.
    return documented_dependencies() + [
        Dependency(source_id="payment", target_id="auth")
    ];
}

def healthy_states -> dict[str, str] {
    states: dict[str, str] = {};
    for service in initial_services() {
        states[service.id] = "healthy";
    }
    return states;
}

def propagate_failure(root_fault: str) -> dict[str, str] {
    # An edge means source depends on target, so failure travels target -> source.
    states = healthy_states();
    if root_fault == "" {
        return states;
    }
    links = true_dependencies();
    queue: list[str] = [root_fault];
    while len(queue) > 0 {
        current = queue.pop(0);
        if states[current] == "down" {
            continue;
        }
        states[current] = "down";
        for link in links {
            if link.target_id == current {
                queue.append(link.source_id);
            }
        }
    }
    return states;
}
