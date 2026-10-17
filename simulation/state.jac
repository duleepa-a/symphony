"""In-memory deterministic simulation state.

The true graph and injected root fault stay private to the simulation package.
Callers only receive service states, documented links, and accepted discovered
links.
"""

import from contracts {
    Service,
    Dependency,
    DashboardState,
    DashboardSummary,
    OperationEnvelope,
    OperationError,
    Evidence
}
import from catalog { initial_services, documented_dependencies }
import from simulation.incidents {
    INCIDENT_ROOT_FAULTS,
    healthy_states,
    propagate_failure
}

obj SimState {
    has incident_id: str = "normal",
        root_fault: str = "",
        run_counter: int = 0,
        simulation_run_id: str = "initial",
        service_states: dict[str, str] = {},
        discovered: list[Dependency] = [],
        evidence_counter: int = 0,
        evidence_log: dict[str, Evidence] = {};
}

glob sim_state: SimState = SimState();

def failure(code: str, message: str) -> OperationEnvelope {
    return OperationEnvelope(
        status="failed", error=OperationError(code=code, message=message)
    );
}

def is_known_service(service_id: str) -> bool {
    for service in initial_services() {
        if service.id == service_id {
            return True;
        }
    }
    return False;
}

def unknown_service(service_id: str) -> OperationEnvelope {
    return failure("unknown_service", f"Unknown service ID '{service_id}'.");
}

def new_run(incident_id: str) {
    sim_state.run_counter += 1;
    sim_state.simulation_run_id = f"run-{sim_state.run_counter}";
    sim_state.incident_id = incident_id;
    sim_state.root_fault = INCIDENT_ROOT_FAULTS[incident_id];
    sim_state.service_states = propagate_failure(sim_state.root_fault);
    sim_state.discovered = [];
    sim_state.evidence_counter = 0;
    sim_state.evidence_log = {};
}

def current_states -> dict[str, str] {
    if len(sim_state.service_states) == 0 {
        return healthy_states();
    }
    return sim_state.service_states;
}

def current_services -> list[Service] {
    states = current_states();
    services = initial_services();
    for service in services {
        service.state = states[service.id];
    }
    return services;
}

def service_dicts(states: dict[str, str]) -> list[dict[str, str]] {
    return [
        {"id": service.id, "name": service.name, "state": states[service.id]}
        for service in initial_services()
    ];
}

def known_dependencies -> list[Dependency] {
    return documented_dependencies() + sim_state.discovered;
}

def dependency_dict(link: Dependency) -> dict[str, any] {
    return {
        "source_id": link.source_id,
        "target_id": link.target_id,
        "kind": link.kind,
        "evidence_ids": link.evidence_ids
    };
}

def sim_is_current_run(run_id: str) -> bool {
    return run_id == sim_state.simulation_run_id;
}

def sim_dashboard_state -> DashboardState {
    services = current_services();
    healthy = len(
        [
            s
            for s in services
            if s.state == "healthy"
        ]
    );
    degraded = len(
        [
            s
            for s in services
            if s.state == "degraded"
        ]
    );
    failed = len(
        [
            s
            for s in services
            if s.state == "down"
        ]
    );
    return DashboardState(
        services=services,
        dependencies=known_dependencies(),
        summary=DashboardSummary(
            total_services=len(services),
            healthy_services=healthy,
            degraded_services=degraded,
            failed_services=failed,
            discovered_dependencies=len(sim_state.discovered)
        ),
        simulation_run_id=sim_state.simulation_run_id
    );
}

def sim_start_incident(incident_id: str) -> OperationEnvelope {
    if incident_id not in INCIDENT_ROOT_FAULTS {
        return failure(
            "unknown_incident",
            f"Unknown incident '{incident_id}'. Use normal, auth_outage, or payment_outage."
        );
    }
    new_run(incident_id);
    return OperationEnvelope(
        status="completed",
        data={
            "incident_id": incident_id,
            "services": service_dicts(sim_state.service_states),
            "simulation_run_id": sim_state.simulation_run_id
        }
    );
}

def sim_reset -> OperationEnvelope {
    new_run("normal");
    return OperationEnvelope(
        status="completed",
        data={
            "incident_id": "normal",
            "services": service_dicts(sim_state.service_states),
            "dependencies": [dependency_dict(e) for e in known_dependencies()],
            "simulation_run_id": sim_state.simulation_run_id
        }
    );
}

def sim_accept_discovered_dependency(
    source_id: str, target_id: str, evidence_ids: list[str]
) -> OperationEnvelope {
    if not is_known_service(source_id) {
        return unknown_service(source_id);
    }
    if not is_known_service(target_id) {
        return unknown_service(target_id);
    }
    if len(evidence_ids) == 0 {
        return failure(
            "missing_evidence", "A discovered dependency needs trace evidence."
        );
    }
    for known in known_dependencies() {
        if known.source_id == source_id and known.target_id == target_id {
            return failure("already_known", "This dependency is already known.");
        }
    }
    supported = False;
    for evidence_id in evidence_ids {
        evidence = sim_state.evidence_log.get(evidence_id);
        if evidence is None {
            return failure(
                "unknown_or_stale_evidence",
                f"Evidence '{evidence_id}' is not part of the active simulation run."
            );
        }
        if evidence.tool != "trace_requests"
        or evidence.simulation_run_id != sim_state.simulation_run_id {
            return failure(
                "unsupported_evidence",
                f"Evidence '{evidence_id}' is not runtime request-trace evidence for this run."
            );
        }
        for span in evidence.observation["spans"] {
            if evidence.service_id == source_id
            and span["direction"] == "outgoing"
            and span["peer"] == target_id {
                supported = True;
            }
            if evidence.service_id == target_id
            and span["direction"] == "incoming"
            and span["peer"] == source_id {
                supported = True;
            }
        }
    }
    if not supported {
        return failure(
            "evidence_does_not_support_edge",
            "The cited traces do not show a request between these services."
        );
    }
    link = Dependency(
        source_id=source_id,
        target_id=target_id,
        kind="discovered",
        evidence_ids=evidence_ids
    );
    sim_state.discovered.append(link);
    return OperationEnvelope(status="completed", data=dependency_dict(link));
}
