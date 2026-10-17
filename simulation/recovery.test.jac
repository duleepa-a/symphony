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

test "repair options list every action without revealing which fits" {
    options = sim_list_repair_options().data["options"];
    assert [o["action"] for o in options] == ["restart", "rollback", "failover"];
    assert "auth" not in str(options) and "payment" not in str(options);
}

test "restart repairs the auth outage and rollback repairs the payment outage" {
    sim_start_incident("auth_outage");
    assert sim_preview_repair("auth", "restart").data["outcome"] == "recovered";
    assert sim_preview_repair("auth", "rollback").data["outcome"] == "not_recovered";
    sim_start_incident("payment_outage");
    assert sim_preview_repair("payment", "rollback").data["outcome"] == "recovered";
    assert sim_preview_repair("payment", "restart").data["outcome"] == "not_recovered";
}

test "failover and wrong targets never recover and do not mutate state" {
    sim_start_incident("auth_outage");
    assert sim_preview_repair("auth", "failover").data["outcome"] == "not_recovered";
    assert sim_preview_repair("payment", "restart").data["outcome"] == "not_recovered";
    assert current_states()["auth"] == "down";
}

test "repair preview reports no incident and rejects bad input" {
    sim_reset();
    assert sim_preview_repair("auth", "restart").data["outcome"] == "no_incident";
    assert sim_preview_repair("nope", "restart").status == "failed";
    bad = sim_preview_repair("auth", "reboot_everything");
    assert bad.error is not None;
    assert bad.status == "failed" and bad.error.code == "unknown_repair_action";
}

test "repair preview output never leaks the fault" {
    sim_start_incident("payment_outage");
    text = str(sim_preview_repair("payment", "restart").data);
    assert "bad_release" not in text and "crashed_process" not in text;
    assert "root_fault" not in text and "fault_kind" not in text;
}
