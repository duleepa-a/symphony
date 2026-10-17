"""Dashboard integration tests: no live model calls, scans, or simulator dependency."""
import from contracts { OperationEnvelope, OperationError }
import from integration.ports { configure_ports, FeaturePorts }
import from integration.gateway { invoke, read_dashboard, discovery_is_supported }
import from tests.dashboard_fixtures { fixture_ports, set_fixture_case }

def error_code(result: OperationEnvelope) -> str {
    return result.error.code if result.error else "";
}

test "unconnected features and invalid inputs remain explicit" {
    configure_ports(FeaturePorts());
    assert invoke("scan_service_dependencies", {"service_id": "payment"}).status == "not_implemented";
    assert error_code(invoke("run_investigation", {})) == "investigator_not_connected";
    assert error_code(invoke("run_security_analysis", {"service_id": "payment"})) == "security_analyst_not_connected";
    assert error_code(invoke("run_recovery_agent", {})) == "recovery_agent_not_connected";
    assert error_code(invoke("run_security_analysis", {"service_id": "unknown"})) == "invalid_service";
    assert error_code(invoke("start_incident", {"incident_id": "unsupported"})) == "invalid_incident";
    assert error_code(
        invoke("scan_service_dependencies", {"service_id": "unknown"})
    ) == "invalid_service";
    initial = read_dashboard();
    assert len(initial.services) == 6 and len(initial.dependencies) == 5;
    assert not `any(
        d.source_id == "payment" and d.target_id == "auth" for d in initial.dependencies
    );
}

test "incident adapters refresh six-service state and reset creates a fresh run" {
    configure_ports(fixture_ports());
    auth = invoke("start_incident", {"incident_id": "auth_outage"});
    assert auth.status == "completed";
    down = [
        s.id
        for s in read_dashboard().services
        if s.state == "down"
    ];
    assert set(down) == {"auth", "payment", "api_gateway", "frontend"};
    old = read_dashboard().simulation_run_id;
    reset = invoke("reset_incident", {});
    assert reset.status == "completed" and old != read_dashboard().simulation_run_id;
    assert all(s.state == "healthy" for s in read_dashboard().services);
    assert len(read_dashboard().dependencies) == 5;
}

test "scanner fixtures preserve completion and failure classes" {
    configure_ports(fixture_ports());
    for case_name in ["completed", "empty", "partial", "failed"] {
        set_fixture_case(case_name);
        result = invoke("scan_service_dependencies", {"service_id": "payment"});
        assert result.status == ("completed" if case_name == "empty" else case_name);
        if case_name == "failed" {
            assert result.error is not None;
        } else {
            assert len(result.data["packages"]) == 1;
        }
    }
}

test "discovery requires the matching run and trace endpoints" {
    configure_ports(fixture_ports());
    set_fixture_case("completed");
    result = invoke("run_investigation", {});
    assert result.status == "completed";
    run_id = read_dashboard().simulation_run_id;
    assert discovery_is_supported(result.data, run_id);
    assert not discovery_is_supported(result.data, "older-run");
    unsupported = {
        ** result.data,
        "discovered_dependencies": [
            {
                "source_id": "auth",
                "target_id": "database",
                "evidence_ids": [f"trace-{run_id}"]
            }
        ]
    };
    assert not discovery_is_supported(unsupported, run_id);
    invented = {
        ** result.data,
        "discovered_dependencies": [
            {
                "source_id": "payment",
                "target_id": "auth",
                "evidence_ids": [f"trace-{run_id}", "invented-id"]
            }
        ]
    };
    assert not discovery_is_supported(invented, run_id);
    assert len(result.data["tool_timeline"]) == 2
    and len(result.data["discovered_dependencies"]) == 1;
}

test "recovery preview preserves the active simulation" {
    configure_ports(fixture_ports());
    invoke("start_incident", {"incident_id": "payment_outage"});
    before = [s.state for s in read_dashboard().services];
    result = invoke("preview_recovery", {"service_id": "payment"});
    assert len(result.data["before"]) == 6 and result.data["outcome"];
    assert [s.state for s in read_dashboard().services] == before;
}

def broken_provider(service_id: str) -> OperationEnvelope {
    raise RuntimeError("provider failure");
}

test "provider exceptions return a failed operation instead of successful empty data" {
    configure_ports(
        FeaturePorts(handlers={"scan_service_dependencies": broken_provider})
    );
    result = invoke("scan_service_dependencies", {"service_id": "payment"});
    assert result.status == "failed"
    and error_code(result) == "feature_execution_failed";
    assert not result.data;
}


def malformed_provider(service_id: str) -> OperationEnvelope {
    return OperationEnvelope(status="completed");
}

def stale_provider(service_id: str) -> OperationEnvelope {
    return OperationEnvelope(status="failed", data={"simulation_run_id": "older"});
}

test "malformed and stale feature responses are rejected" {
    configure_ports(
        FeaturePorts(handlers={"scan_service_dependencies": malformed_provider})
    );
    assert error_code(
        invoke("scan_service_dependencies", {"service_id": "payment"})
    ) == "invalid_feature_response";
    configure_ports(
        FeaturePorts(handlers={"scan_service_dependencies": stale_provider})
    );
    assert error_code(
        invoke("scan_service_dependencies", {"service_id": "payment"})
    ) == "stale_run";
}
