import from simulation.state {
    sim_start_incident,
    sim_reset,
    sim_accept_discovered_dependency
}
import from simulation.diagnostics { sim_trace_requests }

test "database impact reaches all upstream services via documented edges" {
    sim_reset();
    result = sim_analyze_impact("database");
    assert result.status == "completed";
    assert set(result.data["dependent_services"]) == {
        "payment",
        "catalog",
        "api_gateway",
        "frontend"
    };
    assert result.data["priority"] == "high";
}

test "auth has no dependents until the edge is discovered" {
    sim_start_incident("auth_outage");
    assert sim_analyze_impact("auth").data["dependent_services"] == [];
    ev = sim_trace_requests("payment").data;
    sim_accept_discovered_dependency("payment", "auth", [ev["id"]]);
    dependents = sim_analyze_impact("auth").data["dependent_services"];
    assert set(dependents) == {"payment", "api_gateway", "frontend"};
}

test "impact wording avoids unsupported claims" {
    sim_reset();
    for line in sim_analyze_impact("database").data["potential_exposure"] {
        assert "no direct evidence" in str(line);
    }
}

test "impact rejects unknown service" {
    assert sim_analyze_impact("nope").status == "failed";
}
