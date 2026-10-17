test "normal state has all six services healthy" {
    result = sim_start_incident("normal");
    assert result.status == "completed";
    assert len(result.data["services"]) == 6;
    for service in result.data["services"] {
        assert service["state"] == "healthy";
    }
}

test "auth outage propagates to dependents" {
    sim_start_incident("auth_outage");
    states = current_states();
    assert states["auth"] == "down";
    assert states["payment"] == "down";
    assert states["api_gateway"] == "down";
    assert states["frontend"] == "down";
    assert states["catalog"] == "healthy";
    assert states["database"] == "healthy";
}

test "payment outage propagates to dependents only" {
    sim_start_incident("payment_outage");
    states = current_states();
    assert states["payment"] == "down";
    assert states["api_gateway"] == "down";
    assert states["frontend"] == "down";
    assert states["auth"] == "healthy";
    assert states["catalog"] == "healthy";
    assert states["database"] == "healthy";
}

test "unknown incident is rejected" {
    result = sim_start_incident("bogus");
    assert result.status == "failed";
    assert result.error?.code == "unknown_incident";
}

test "reset restores healthy state with a new run id and no discovered edges" {
    sim_start_incident("auth_outage");
    old_run = sim_state.simulation_run_id;
    result = sim_reset();
    assert result.status == "completed";
    assert result.data["simulation_run_id"] != old_run;
    assert len(sim_state.discovered) == 0;
    assert len(result.data["dependencies"]) == 5;
    for service in result.data["services"] {
        assert service["state"] == "healthy";
    }
}

test "dashboard state starts with five documented dependencies only" {
    sim_reset();
    state = sim_dashboard_state();
    assert len(state.services) == 6;
    assert len(state.dependencies) == 5;
    for dep in state.dependencies {
        assert dep.kind == "documented";
    }
}
