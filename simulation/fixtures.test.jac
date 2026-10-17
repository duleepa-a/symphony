import from simulation.state { sim_start_incident, sim_reset }
import from simulation.diagnostics { sim_check_health }

test "service fixtures match the live simulation for every scenario" {
    for incident_id in ["normal", "auth_outage", "payment_outage"] {
        live = sim_start_incident(incident_id);
        fixture = fixture_start_incident(incident_id);
        assert fixture["status"] == live.status;
        assert fixture["data"]["services"] == live.data["services"];
        for service_id in SERVICE_ORDER {
            live_obs = sim_check_health(service_id).data["observation"];
            fixture_obs = fixture_health(service_id, incident_id)["data"][
                "observation"
            ];
            assert live_obs["state"] == fixture_obs["state"];
        }
    }
}

test "reset fixture has five documented dependencies" {
    live = sim_reset();
    fixture = fixture_reset();
    assert len(fixture["data"]["dependencies"]) == 5;
    assert fixture["data"]["dependencies"] == live.data["dependencies"];
}

test "unknown service fixture matches the live error" {
    live = sim_check_health("nope");
    fixture = fixture_unknown_service();
    assert fixture["status"] == live.status;
    assert fixture["error"]["code"] == live.error?.code;
}
