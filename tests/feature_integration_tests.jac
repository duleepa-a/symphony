"""Cross-feature acceptance: real simulator and Investigator tools, no paid model calls."""
import json;
import from unittest.mock { patch }
import investigation.agent as agent;
import from jaclang.byllm.lib { MockLLM, MockToolCall, AuthenticationError, ModelPool }
import from contracts {
    Dependency,
    Evidence,
    InvestigationResult,
    OperationEnvelope,
    PackageInventoryItem
}
import from integration.bindings { production_ports }
import from integration.ports { configure_ports }
import from integration.gateway { invoke, read_dashboard }
import from integration.investigation_adapter { investigate_with }
import from integration.security_adapter { normalize_scan }
import from integration.evidence { supports_dependency }
import from investigation.tools {
    prepare_diagnostic_run,
    trace_requests_tool,
    investigation_evidence,
    investigation_tool_timeline
}
import from investigation.validation {
    validate_investigation_result,
    investigation_result_to_dict
}
import from security.osv { scan_inventory_with_transport }
import from simulation.state { sim_reset }

def finish_tool(final_output: InvestigationResult) -> InvestigationResult {
    return final_output;
}

glob mock_model = MockLLM(
         model_name="mockllm", config={"outputs": [], "verbose": False}
     );

def model_runner(context: str, run_id: str) -> OperationEnvelope {
    assert "root_fault" not in context and "true_dependencies" not in context;
    public_context = json.loads(context);
    assert len(public_context["documented_dependencies"]) == 5;
    mock_model = MockLLM(
        model_name="mockllm",
        config={
            "outputs": [
                MockToolCall(tool=trace_requests_tool, args={"service_id": "payment"}),
                MockToolCall(
                    tool=finish_tool,
                    args={
                        "final_output": InvestigationResult(
                            status="completed",
                            candidate_root_causes=["Auth is unavailable"],
                            discovered_dependencies=[
                                Dependency(
                                    source_id="payment",
                                    target_id="auth",
                                    kind="discovered",
                                    evidence_ids=[f"{run_id}-ev-1"]
                                )
                            ],
                            explanation="Payment's observed outgoing Auth request timed out."
                        )
                    }
                )
            ],
            "verbose": False
        }
    );
    with patch.object(agent, "investigator_model", mock_model) {
        return agent.run_investigation_impl(context, run_id);
    }
}

test "production bindings drive both incidents and recovery without mutations" {
    configure_ports(production_ports());
    for (scenario, expected) in [
        ("auth_outage", {"auth", "payment", "api_gateway", "frontend"}),
        ("payment_outage", {"payment", "api_gateway", "frontend"})
    ] {
        assert invoke("start_incident", {"incident_id": scenario}).status == "completed";
        snapshot = read_dashboard();
        assert {
            service.id
            for service in snapshot.services
            if service.state == "down"
        } == expected;
        assert len(snapshot.dependencies) == 5;
        for operation in [
            "check_service_health",
            "get_service_logs",
            "trace_requests"
        ] {
            result = invoke(operation, {"service_id": "payment"});
            assert result.status == "completed";
            assert result.data["simulation_run_id"] == snapshot.simulation_run_id;
            assert "root_fault" not in json.dumps(result.data);
        }
        recovery = invoke(
            "preview_recovery",
            {"service_id": "auth" if scenario == "auth_outage" else "payment"}
        );
        assert recovery.data["outcome"] == "recovered";
        assert all(service["state"] == "healthy" for service in recovery.data["after"]);
        assert [service.state for service in read_dashboard().services] == [
            service.state for service in snapshot.services
        ];
    }
    old_run = read_dashboard().simulation_run_id;
    assert invoke("reset_incident", {}).status == "completed";
    assert read_dashboard().simulation_run_id != old_run;
    assert all(service.state == "healthy" for service in read_dashboard().services);
}

def integrated_mock_investigation -> OperationEnvelope {
    return investigate_with(model_runner);
}

test "MockLLM native trace discovery persists into graph and impact then reset clears it" {
    ports = production_ports();
    ports.handlers["run_investigation"] = integrated_mock_investigation;
    configure_ports(ports);
    invoke("start_incident", {"incident_id": "auth_outage"});
    assert invoke("analyze_security_impact", {"service_id": "auth"}).data[
        "dependent_services"
    ] == [];
    result = invoke("run_investigation", {});
    assert result.status == "completed" , str(result.error);
    assert len(result.data["evidence"]) == 1;
    assert "trace_requests(payment)" in str(result.data["tool_timeline"]);
    assert len(read_dashboard().dependencies) == 6;
    assert read_dashboard().summary.discovered_dependencies == 1;
    impact = invoke("analyze_security_impact", {"service_id": "auth"});
    assert set(impact.data["dependent_services"]) == {
        "payment",
        "api_gateway",
        "frontend"
    };
    assert "no direct evidence" in str(impact.data["potential_exposure"]);
    invoke("reset_incident", {});
    assert len(read_dashboard().dependencies) == 5;
    assert read_dashboard().summary.discovered_dependencies == 0;
}

def resetting_runner(context: str, run_id: str) -> OperationEnvelope {
    prepare_diagnostic_run(run_id);
    trace_requests_tool("payment");
    sim_reset();
    return OperationEnvelope(
        status="completed",
        data={
            "discovered_dependencies": [
                {
                    "source_id": "payment",
                    "target_id": "auth",
                    "evidence_ids": [investigation_evidence()[0].id]
                }
            ],
            "explanation": "stale"
        }
    );
}

test "reset during investigation rejects stale results before graph mutation" {
    configure_ports(production_ports());
    invoke("start_incident", {"incident_id": "auth_outage"});
    result = investigate_with(resetting_runner);
    assert result.error is not None;
    assert result.status == "failed" and result.error.code == "stale_run";
    assert len(read_dashboard().dependencies) == 5;
}

test "every cited trace must support an actually attempted call in the active run" {
    dependency = Dependency(
        source_id="payment", target_id="auth", evidence_ids=["good", "unrelated"]
    );
    good = Evidence(
        id="good",
        tool="trace_requests",
        service_id="payment",
        simulation_run_id="r",
        observation={
            "spans": [{"direction": "outgoing", "peer": "auth", "outcome": "timeout"}]
        }
    );
    unrelated = Evidence(
        id="unrelated",
        tool="trace_requests",
        service_id="catalog",
        simulation_run_id="r",
        observation={
            "spans": [{"direction": "outgoing", "peer": "database", "outcome": "ok"}]
        }
    );
    assert not supports_dependency(dependency, [good, unrelated], "r");
    dependency.evidence_ids = ["good"];
    assert supports_dependency(dependency, [good], "r");
    assert not supports_dependency(dependency, [good], "old");
    good.observation["spans"][0]["outcome"] = "not_attempted";
    assert not supports_dependency(dependency, [good], "r");
}

def query_fixture(name: str, ecosystem: str, version: str) -> dict[str, any] {
    if name == "broken" {
        raise TimeoutError("OSV timed out");
    }
    return {
        "vulns": [
            {
                "id": "OSV-EXAMPLE",
                "summary": "Example advisory",
                "references": [
                    {
                        "type": "ADVISORY",
                        "url": "https://osv.dev/vulnerability/OSV-EXAMPLE"
                    }
                ]
            }
        ]
    };
}

def detail_fixture(advisory_id: str) -> dict[str, any] {
    return {
        "id": advisory_id,
        "summary": "Example advisory",
        "references": [{"url": "https://osv.dev/"}]
    };
}

test "scanner adapter retains partial failures and advisory identities for dashboard" {
    result = normalize_scan(
        scan_inventory_with_transport(
            "payment",
            [
                PackageInventoryItem(name="example", ecosystem="npm", version="1.0.0"),
                PackageInventoryItem(name="broken", ecosystem="npm", version="1.0.0")
            ],
            query_fixture,
            detail_fixture
        )
    );
    assert result.status == "partial" and result.error is not None;
    assert len(result.data["packages"]) == 2;
    assert result.data["packages"][0]["advisories"][0]["id"] == "OSV-EXAMPLE";
    assert result.data["packages"][0]["advisories"][0]["severity"] == "unknown";
    assert "timed out" in str(result.data["packages"][1]["error"]["message"]);
}


def authentication_failure(context: str, run_id: str) -> InvestigationResult {
    raise AuthenticationError("Fixture authentication rejection.");
}

test "live Investigator binding preserves provider failure status without graph mutations" {
    configure_ports(production_ports());
    invoke("start_incident", {"incident_id": "auth_outage"});
    previous = agent.investigate_incident_impl;
    try {
        agent.investigate_incident_impl = authentication_failure;
        result = invoke("run_investigation", {});
        assert result.status == "failed";
        assert result.error is not None;
        assert result.error.code == "investigator_authentication_error";
        assert len(read_dashboard().dependencies) == 5;
    } finally {
        agent.investigate_incident_impl = previous;
    }
}
