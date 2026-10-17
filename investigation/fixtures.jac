"""Deterministic diagnostic fixtures matching the frozen Evidence contract."""

import from contracts { Dependency, Evidence, InvestigationResult }

obj DiagnosticFixtureState {
    has simulation_run_id: str = "fixture-auth-run",
        tool_timeline: list[str] = [],
        evidence: list[Evidence] = [];
}

glob fixture_state = DiagnosticFixtureState();
glob VALID_SERVICE_IDS = [
         "frontend",
         "api_gateway",
         "payment",
         "catalog",
         "auth",
         "database",

     ];

def reset_diagnostic_fixtures(simulation_run_id: str = "fixture-auth-run") {
    fixture_state.simulation_run_id = simulation_run_id;
    fixture_state.tool_timeline.clear();
    fixture_state.evidence.clear();
}

def _require_service(service_id: str) {
    if service_id not in VALID_SERVICE_IDS {
        raise ValueError(f"Unknown service ID: {service_id}");
    }
}

def _record_evidence(
    tool: str, service_id: str, observation: dict[str, any],
) -> Evidence {
    evidence = Evidence(
        id=f"{tool}-{service_id}-{len(fixture_state.evidence) + 1}",
        tool=tool,
        service_id=service_id,
        observation=observation,
        simulation_run_id=fixture_state.simulation_run_id,
    );
    fixture_state.tool_timeline.append(f"{tool}({service_id})");
    fixture_state.evidence.append(evidence);
    return evidence;
}

def check_service_health_fixture(service_id: str) -> Evidence {
    _require_service(service_id);
    state = "down"
        if service_id in ["auth", "payment", "api_gateway", "frontend"]
        else "healthy";
    return _record_evidence(
        "check_service_health",
        service_id,
        {"state": state, "source": "simulated health probe"},
    );
}

sem check_service_health_fixture = "Check observable health for one simulated service. This tool never returns the injected fault or private graph.";
sem check_service_health_fixture.service_id = "Stable service ID to inspect.";

def get_service_logs_fixture(service_id: str) -> Evidence {
    _require_service(service_id);
    message = "requests completing normally";
    if service_id == "auth" {
        message = "token validation endpoint unavailable";
    } elif service_id == "payment" {
        message = "checkout requests failing during token validation";
    } elif service_id in ["api_gateway", "frontend"] {
        message = "upstream checkout requests failing";
    }
    return _record_evidence(
        "get_service_logs",
        service_id,
        {
            "level": "error"
                if service_id in ["auth", "payment", "api_gateway", "frontend"]
                else "info",
            "message": message
        },
    );
}

sem get_service_logs_fixture = "Read deterministic observable logs for one service. Logs expose symptoms, not hidden simulator state.";
sem get_service_logs_fixture.service_id = "Stable service ID whose logs should be inspected.";

def trace_requests_fixture(service_id: str) -> Evidence {
    _require_service(service_id);
    observation: dict[str, any] = {
        "source_id": service_id,
        "target_id": "database"
            if service_id in ["payment", "catalog"]
            else "api_gateway",
        "status": "ok",

    };
    if service_id == "payment" {
        observation = {
            "source_id": "payment",
            "target_id": "auth",
            "request": "POST /token/validate",
            "status": "connection_refused",

        };
    }
    return _record_evidence("trace_requests", service_id, observation);
}

sem trace_requests_fixture = "Inspect observed request traces for one service. Trace evidence may support a previously undocumented dependency.";
sem trace_requests_fixture.service_id = "Stable service ID whose incoming or outgoing calls should be traced.";

def recorded_tool_timeline -> list[str] {
    return fixture_state.tool_timeline.copy();
}

def recorded_evidence -> list[Evidence] {
    return fixture_state.evidence.copy();
}

def completed_investigation_fixture -> InvestigationResult {
    return InvestigationResult(
        status="completed",
        candidate_root_causes=["Auth outage interrupts Payment token validation"],
        discovered_dependencies=[
            Dependency(
                source_id="payment",
                target_id="auth",
                kind="discovered",
                evidence_ids=["trace_requests-payment-1"],
            )
        ],
        explanation="Payment traces show failed calls to Auth during checkout.",
    );
}

def failed_investigation_fixture -> InvestigationResult {
    return InvestigationResult(
        status="failed",
        explanation="No current-run diagnostic evidence was available.",
    );
}

def stale_evidence_fixture -> list[Evidence] {
    return [
        Evidence(
            id="trace_requests-payment-stale",
            tool="trace_requests",
            service_id="payment",
            observation={"source_id": "payment", "target_id": "auth"},
            simulation_run_id="previous-run",
        )
    ];
}
