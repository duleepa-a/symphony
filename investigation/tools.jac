"""Injectable diagnostic tool boundary for independent and integrated runs."""

import from contracts { Evidence }
import from .fixtures {
    check_service_health_fixture,
    get_service_logs_fixture,
    reset_diagnostic_fixtures,
    trace_requests_fixture,
}

glob health_provider: Callable[[str], Evidence] = check_service_health_fixture;
glob logs_provider: Callable[[str], Evidence] = get_service_logs_fixture;
glob traces_provider: Callable[[str], Evidence] = trace_requests_fixture;
glob fixture_providers_active = True;
glob actual_tool_timeline: list[str] = [];
glob actual_evidence: list[Evidence] = [];

def configure_diagnostic_tools(
    health: Callable[[str], Evidence],
    logs: Callable[[str], Evidence],
    traces: Callable[[str], Evidence],
) {
    health_provider = health;
    logs_provider = logs;
    traces_provider = traces;
    fixture_providers_active = False;
}

def use_fixture_diagnostic_tools {
    health_provider = check_service_health_fixture;
    logs_provider = get_service_logs_fixture;
    traces_provider = trace_requests_fixture;
    fixture_providers_active = True;
}

def prepare_diagnostic_run(simulation_run_id: str) {
    actual_tool_timeline.clear();
    actual_evidence.clear();
    if fixture_providers_active {
        reset_diagnostic_fixtures(simulation_run_id);
    }
}

def _record_tool_result(tool: str, service_id: str, evidence: Evidence) -> Evidence {
    actual_tool_timeline.append(f"{tool}({service_id})");
    actual_evidence.append(evidence);
    return evidence;
}

def check_service_health_tool(service_id: str) -> Evidence {
    return _record_tool_result(
        "check_service_health", service_id, health_provider(service_id)
    );
}

sem check_service_health_tool = "Check observable health for one simulated service. This tool never returns the injected fault or private graph.";
sem check_service_health_tool.service_id = "Stable service ID to inspect.";

def get_service_logs_tool(service_id: str) -> Evidence {
    return _record_tool_result(
        "get_service_logs", service_id, logs_provider(service_id)
    );
}

sem get_service_logs_tool = "Read observable logs for one simulated service. Logs expose symptoms, not hidden simulator state.";
sem get_service_logs_tool.service_id = "Stable service ID whose logs should be inspected.";

def trace_requests_tool(service_id: str) -> Evidence {
    return _record_tool_result(
        "trace_requests", service_id, traces_provider(service_id)
    );
}

sem trace_requests_tool = "Inspect observed request traces for one service. Trace evidence may support a previously undocumented dependency.";
sem trace_requests_tool.service_id = "Stable service ID whose incoming or outgoing calls should be traced.";

def investigation_tool_timeline -> list[str] {
    return actual_tool_timeline.copy();
}

def investigation_evidence -> list[Evidence] {
    return actual_evidence.copy();
}
