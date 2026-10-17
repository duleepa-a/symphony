import from simulation.state { sim_start_incident, sim_reset }

test "repairing the origin recovers everything without mutating active state" {
    sim_start_incident("auth_outage");
    result = sim_preview_recovery("auth");
    assert result.data["outcome"] == "recovered";
    for service in result.data["after"] {
        assert service["state"] == "healthy";
    }
    down_before = [
        s
        for s in result.data["before"]
        if s["state"] == "down"
    ];
    assert len(down_before) == 4;
    assert current_states()["auth"] == "down";
}

test "repairing a dependent does not recover" {
    sim_start_incident("payment_outage");
    result = sim_preview_recovery("frontend");
    assert result.data["outcome"] == "not_recovered";
    assert current_states()["payment"] == "down";
}

test "recovery preview with no incident" {
    sim_reset();
    assert sim_preview_recovery("auth").data["outcome"] == "no_incident";
}

test "recovery rejects unknown service" {
    assert sim_preview_recovery("nope").status == "failed";
}
