"""Dashboard integration tests: no live model calls, scans, or simulator dependency."""
import from contracts { OperationEnvelope, OperationError, Dependency }
import from integration.ports { configure_ports, FeaturePorts }
import from integration.gateway { invoke, read_dashboard, discovery_is_supported }
import from tests.dashboard_fixtures {
    fixture_ports,
    set_fixture_case,
    fixture_dashboard
}
import from dashboard.models.view_models {
    scan_view,
    investigation_view,
    recovery_view,
    request_is_current,
    merge_dependencies,
    safe_advisory_url,
    status_view,
    observation_text
}

def error_code(result: OperationEnvelope) -> str {
    return result.error.code if result.error else "";
}

test "unconnected features and invalid inputs remain explicit" {
    configure_ports(FeaturePorts());
    assert invoke("scan_service_dependencies", {"service_id": "payment"}).status
        == "not_implemented";
    assert error_code(invoke("run_investigation", {})) == "investigator_not_connected";
    assert error_code(invoke("start_incident", {"incident_id": "unsupported"}))
        == "invalid_incident";
    assert error_code(invoke("scan_service_dependencies", {"service_id": "unknown"}))
        == "invalid_service";
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

test "scanner separates findings empty partial and failed cases" {
    configure_ports(fixture_ports());
    for case_name in ["completed", "empty", "partial", "failed"] {
        set_fixture_case(case_name);
        result = scan_view(
            invoke("scan_service_dependencies", {"service_id": "payment"}), "payment"
        );
        assert result.feedback.status
            == ("completed" if case_name == "empty" else case_name);
        if case_name == "completed" {
            assert result.finding_count == 1;
            assert result.packages[0].advisories[0].severity == "unknown";
        } elif case_name == "empty" {
            assert result.packages[0].status == "completed"
                and result.finding_count == 0;
        } elif case_name == "partial" {
            assert result.packages[0].error and result.finding_count == 1;
        } else {
            assert not result.packages and result.feedback.message;
        }
    }
}

test "empty malformed scans and unsafe links never become clean successful data" {
    result = scan_view(
        OperationEnvelope(status="completed", data={"packages": []}), "payment"
    );
    assert result.feedback.status == "failed";
    assert safe_advisory_url("javascript:alert(1)") == "";
    assert safe_advisory_url("https://osv.dev/vulnerability/FIXTURE") != "";
    assert status_view(OperationEnvelope(status="unexpected")).status == "failed";
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
    presentation = investigation_view(result);
    assert len(presentation.timeline) == 2 and len(presentation.dependencies) == 1;
}

test "request guard discards old runs old services old requests and old epochs" {
    assert request_is_current(
        1, 1, 2, 2, "payment", "payment", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 2, 2, 2, "payment", "payment", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 1, 1, 2, "payment", "payment", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 1, 2, 2, "payment", "catalog", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 1, 2, 2, "payment", "payment", "run-1", "run-2", "run-1"
    );
    assert not request_is_current(
        1, 1, 2, 2, "payment", "payment", "run-1", "run-1", "run-0"
    );
}

test "discovered edges deduplicate and require evidence references" {
    documented = [Dependency(source_id="payment", target_id="database")];
    proposed = [
        Dependency(
            source_id="payment",
            target_id="auth",
            kind="discovered",
            evidence_ids=["trace-1"]
        )
    ];
    assert len(merge_dependencies(documented, proposed + proposed)) == 2;
    assert len(
        merge_dependencies(
            documented,
            [Dependency(source_id="payment", target_id="auth", kind="discovered")]
        )
    )
        == 1;
}

test "recovery preview preserves the active simulation" {
    configure_ports(fixture_ports());
    invoke("start_incident", {"incident_id": "payment_outage"});
    before = [s.state for s in read_dashboard().services];
    view = recovery_view(invoke("preview_recovery", {"service_id": "payment"}));
    assert len(view.rows) == 6 and view.outcome;
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
    assert error_code(invoke("scan_service_dependencies", {"service_id": "payment"}))
        == "invalid_feature_response";
    configure_ports(
        FeaturePorts(handlers={"scan_service_dependencies": stale_provider})
    );
    assert error_code(invoke("scan_service_dependencies", {"service_id": "payment"}))
        == "stale_run";
}

test "evidence formatting retains concrete observations" {
    description = observation_text(
        {"source_id": "payment", "target_id": "auth", "message": "timeout"}
    );
    assert "payment" in description
        and "auth" in description
        and "timeout" in description;
}
