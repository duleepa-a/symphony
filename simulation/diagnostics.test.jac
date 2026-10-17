import json;
import from simulation.state {
    sim_start_incident,
    sim_reset,
    sim_is_current_run,
    sim_accept_discovered_dependency,
    sim_dashboard_state
}

def trace_for(service_id: str) -> dict[str, any] {
    return sim_trace_requests(service_id).data;
}

test "health reflects incident" {
    sim_start_incident("auth_outage");
    assert sim_check_health("auth").data["observation"]["state"] == "down";
    assert sim_check_health("catalog").data["observation"]["state"] == "healthy";
}

test "evidence carries unique ids and the active run id" {
    sim_start_incident("auth_outage");
    first = sim_check_health("auth").data;
    second = sim_get_logs("auth").data;
    assert first["id"] != second["id"];
    assert first["simulation_run_id"] == sim_state.simulation_run_id;
}

test "unknown service is rejected by every tool" {
    for result in [
        sim_check_health("nope"),
        sim_get_logs("nope"),
        sim_trace_requests("nope")
    ] {
        assert result.status == "failed";
        assert result.error?.code == "unknown_service";
    }
}

test "diagnostics never leak the fault or true graph" {
    sim_start_incident("auth_outage");
    for service_id in [
        "frontend",
        "api_gateway",
        "payment",
        "catalog",
        "auth",
        "database"
    ] {
        for result in [
            sim_check_health(service_id),
            sim_get_logs(service_id),
            sim_trace_requests(service_id)
        ] {
            text = json.dumps(result.data).lower();
            assert "root_fault" not in text;
            assert "true_graph" not in text;
            assert "propagat" not in text;
            assert "auth_outage" not in text;
        }
    }
}

test "payment trace during auth outage shows failed auth call" {
    sim_start_incident("auth_outage");
    spans = trace_for("payment")["observation"]["spans"];
    found = [
        s
        for s in spans
        if s["direction"] == "outgoing" and s["peer"] == "auth"
    ];
    assert len(found) == 1;
    assert found[0]["outcome"] == "timeout";
}

test "trace evidence promotes payment to auth as a discovered edge" {
    sim_start_incident("auth_outage");
    ev = trace_for("payment");
    result = sim_accept_discovered_dependency("payment", "auth", [ev["id"]]);
    assert result.status == "completed";
    assert result.data["kind"] == "discovered";
    assert sim_dashboard_state().summary.discovered_dependencies == 1;
}

test "health evidence cannot support a discovered edge" {
    sim_start_incident("auth_outage");
    ev = sim_check_health("payment").data;
    result = sim_accept_discovered_dependency("payment", "auth", [ev["id"]]);
    assert result.status == "failed";
    assert result.error?.code == "unsupported_evidence";
}

test "trace without a matching span cannot support an edge" {
    sim_start_incident("auth_outage");
    ev = trace_for("catalog");
    result = sim_accept_discovered_dependency("catalog", "auth", [ev["id"]]);
    assert result.status == "failed";
    assert result.error?.code == "evidence_does_not_support_edge";
}

test "reset invalidates evidence from the previous run" {
    sim_start_incident("auth_outage");
    ev = trace_for("payment");
    sim_reset();
    result = sim_accept_discovered_dependency("payment", "auth", [ev["id"]]);
    assert result.status == "failed";
    assert result.error?.code == "unknown_or_stale_evidence";
    assert not sim_is_current_run(ev["simulation_run_id"]);
}
