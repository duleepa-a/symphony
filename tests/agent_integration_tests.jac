"""Agent integration checkpoint: actual fact layer and MockLLM, no live providers."""
import from dataclasses { asdict }
import from threading { Barrier }
import from concurrent.futures { ThreadPoolExecutor }
import from jaclang.byllm.lib { MockLLM }
import from contracts {
    Dependency,
    Evidence,
    InvestigationResult,
    OperationEnvelope,
    OperationError,
    SecurityAssessment,
    AssessedFinding,
    RecoveryProposal,
    RepairPreview
}
import from integration.agent_ports { AgentPorts, AgentSession }
import from integration.bindings { production_ports }
import from integration.ports { configure_ports }
import from integration.gateway { invoke, read_dashboard }
import from integration.result_store { result_store, result_lock, ResultStore }
import from simulation.state { sim_accept_discovered_dependency }
import from simulation.diagnostics { sim_trace_requests }
import from simulation.recovery { sim_preview_recovery }

glob mode: str = "completed",
     repair_target: str = "auth";
glob security_model = MockLLM(model_name="mockllm", config={"outputs": []});
glob recovery_model = MockLLM(model_name="mockllm", config={"outputs": []});
def assess(context: str) -> SecurityAssessment by security_model();
obj RepairDecision {
    has target_service_id: str,
        action: str,
        rationale: str,
        cited_evidence_ids: list[str] = [];
}

def propose(context: str) -> RepairDecision by recovery_model();

def scan_fixture(service_id: str) -> OperationEnvelope {
    if mode == "failed_scan" {
        return OperationEnvelope(
            status="failed",
            error=OperationError(
                code="fixture_osv_failure", message="Offline fixture failed."
            )
        );
    }
    advisories: list[dict[str, any]] = []
        if mode == "empty"
        else [{"id": "ADV-1", "summary": "Offline fixture", "severity": "unknown"}];
    return OperationEnvelope(
        status="partial" if mode == "partial" else "completed",
        data={
            "service_id": service_id,
            "inventory": [],
            "packages": [{"name": "fixture", "advisories": advisories}],
            "finding_count": len(advisories)
        }
    );
}

def investigation_fixture -> OperationEnvelope {
    trace = sim_trace_requests("payment");
    return OperationEnvelope(
        status="completed",
        data={
            "simulation_run_id": read_dashboard().simulation_run_id,
            "evidence": [trace.data],
            "tool_timeline": ["trace_requests(payment)"],
            "discovered_dependencies": [],
            "explanation": "Offline investigation observed the actual simulator trace."
        }
    );
}

def security_fixture(session: AgentSession) -> OperationEnvelope {
    scan: OperationEnvelope = session.read("scan_results");
    impact: OperationEnvelope = session.read("impact");
    assert "root_fault" not in str(session.facts)
    and "true_dependencies" not in str(session.facts);
    findings: list[AssessedFinding] = [];
    if scan.data["finding_count"] {
        findings = [
            AssessedFinding(
                advisory_id="ADV-1",
                package="fixture",
                risk="Review the cited advisory for this exact package.",
                cited_advisory_ids=["ADV-1"]
            )
        ];
    }
    security_model = MockLLM(
        model_name="mockllm",
        config={
            "outputs": [
                SecurityAssessment(
                    service_id=session.service_id,
                    simulation_run_id=session.simulation_run_id,
                    findings=findings,
                    dependents=impact.data["dependent_services"],
                    priority="low",
                    explanation="Prioritize review of the cited package advisory."
                        if findings
                        else "No advisories returned in the completed exact-version scan."
                )
            ],
            "verbose": False
        }
    );
    result = OperationEnvelope(status="completed", data=asdict(assess(str(scan.data))));
    if mode == "invented" {
        result.data["findings"][0]["cited_advisory_ids"] = ["INVENTED"];
    }
    if mode == "old_run" {
        result.data["simulation_run_id"] = "old";
    }
    if mode == "reset" {
        invoke("reset_incident", {});
    }
    if mode == "replace_scan" {
        invoke("scan_service_dependencies", {"service_id": session.service_id});
    }
    if mode == "unsafe_claim" {
        result.data["explanation"] = "API Gateway is compromised.";
    }
    if mode == "all_clear" {
        result.data["explanation"] = "all clear";
    }
    if mode == "discover_during_analysis" {
        trace = invoke("trace_requests", {"service_id": "payment"});
        assert sim_accept_discovered_dependency(
            "payment", "auth", [trace.data["id"]]
        ).status == "completed";
    }
    return result;
}

def recovery_fixture(session: AgentSession) -> OperationEnvelope {
    investigation: OperationEnvelope = session.read("investigation_result");
    assert session.read("repair_options") == ["restart", "rollback", "failover"];
    recovery_model = MockLLM(
        model_name="mockllm",
        config={
            "outputs": [
                RepairDecision(
                    target_service_id=repair_target,
                    action="restart",
                    rationale="The cited diagnostic evidence supports testing this repair.",
                    cited_evidence_ids=[investigation.data["evidence"][0]["id"]]
                )
            ],
            "verbose": False
        }
    );
    result = OperationEnvelope(
        status="completed",
        data={
            ** asdict(propose(str(investigation.data))),
            "simulation_run_id": session.simulation_run_id,
            "preview": {"outcome": "recovered"}
        }
    );
    if mode == "invented" {
        result.data["cited_evidence_ids"] = ["INVENTED"];
    }
    if mode == "bad_action" {
        result.data["action"] = "erase_database";
    }
    if mode == "replace_investigation" {
        invoke("run_investigation", {});
    }
    return result;
}

def options_fixture -> list[str] {
    return ["restart", "rollback", "failover"];
}

def preview_fixture(service_id: str, action: str) -> OperationEnvelope {
    result = sim_preview_recovery(service_id);
    if action != "restart" {
        result.data["after"] = result.data["before"];
        result.data["outcome"] = "not_recovered";
    }
    return result;
}

def setup {
    mode = "completed";
    repair_target = "auth";
    ports = production_ports(
        AgentPorts(
            security=security_fixture,
            recovery=recovery_fixture,
            repair_options=options_fixture,
            preview=preview_fixture
        )
    );
    ports.handlers["scan_service_dependencies"] = scan_fixture;
    ports.handlers["run_investigation"] = investigation_fixture;
    configure_ports(ports);
    invoke("start_incident", {"incident_id": "auth_outage"});
}

def code(result: OperationEnvelope) -> str {
    return result.error.code if result.error else "";
}

test "agents require current prerequisites and explicit unbound ports remain truthful" {
    configure_ports(production_ports(AgentPorts()));
    invoke("reset_incident", {});
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "scan_required";
    assert code(invoke("run_recovery_agent", {})) == "investigation_required";
    setup();
    invoke("scan_service_dependencies", {"service_id": "payment"});
    invoke("run_investigation", {});
    configure_ports(production_ports(AgentPorts()));
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "security_analyst_not_connected";
    assert code(invoke("run_recovery_agent", {})) == "recovery_agent_not_connected";
}

test "analyst chains latest scan and retains independent rule priority" {
    setup();
    invoke("scan_service_dependencies", {"service_id": "payment"});
    result = invoke("run_security_analysis", {"service_id": "payment"});
    assert result.status == "completed" , str(result.error);
    assert result.data["priority"] == "low";
    assert result.data["rule_based_priority"] == "medium";
    assert result.data["priority_below_rule_based"];
    assert result.data["scan_status"] == "completed";
    assert "_input_revision" not in result.data;
    assert result_store.latest("run_security_analysis", "payment") is not None;
    mode = "invented";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "unsupported_advisory";
    assert invoke("analyze_security_impact", {"service_id": "payment"}).status == "completed";
}

test "failed and partial scans never become a clean assessment" {
    setup();
    mode = "failed_scan";
    invoke("scan_service_dependencies", {"service_id": "payment"});
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "scan_failed";
    mode = "partial";
    invoke("scan_service_dependencies", {"service_id": "payment"});
    result = invoke("run_security_analysis", {"service_id": "payment"});
    assert result.status == "partial" and code(result) == "scan_incomplete";
    mode = "all_clear";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "incomplete_scan_claim";
    mode = "empty";
    invoke("scan_service_dependencies", {"service_id": "payment"});
    result = invoke("run_security_analysis", {"service_id": "payment"});
    assert result.status == "completed" and result.data["findings"] == [];
}

test "stale runs and replacement scans cannot publish an assessment" {
    setup();
    invoke("scan_service_dependencies", {"service_id": "payment"});
    mode = "old_run";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "stale_agent_result";
    mode = "replace_scan";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "stale_prerequisite";
    mode = "reset";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "stale_run";
    assert result_store.latest("run_security_analysis", "payment") is None;
    assert result_store.latest("scan_service_dependencies", "payment") is None;
}

test "recovery chains investigation and trusts simulator rather than model outcome" {
    setup();
    for (incident, target) in [
        ("auth_outage", "auth"),
        ("payment_outage", "payment")
    ] {
        invoke("start_incident", {"incident_id": incident});
        repair_target = target;
        invoke("run_investigation", {});
        before = [service.state for service in read_dashboard().services];
        result = invoke("run_recovery_agent", {});
        assert result.status == "completed" , str(result.error);
        assert result.data["preview"]["outcome"] == "recovered";
        assert before == [service.state for service in read_dashboard().services];
        repair_target = "catalog";
        wrong = invoke("run_recovery_agent", {});
        assert wrong.status == "completed"
        and wrong.data["preview"]["outcome"] == "not_recovered";
    }
    invoke("reset_incident", {});
    invoke("run_investigation", {});
    assert invoke("run_recovery_agent", {}).data["preview"]["outcome"] == "no_incident";
}

test "recovery rejects invented citations actions and replaced investigation" {
    setup();
    invoke("run_investigation", {});
    mode = "invented";
    assert code(invoke("run_recovery_agent", {})) == "unsupported_repair_evidence";
    mode = "bad_action";
    assert code(invoke("run_recovery_agent", {})) == "unsupported_repair";
    mode = "replace_investigation";
    assert code(invoke("run_recovery_agent", {})) == "stale_prerequisite";
    invoke("reset_incident", {});
    assert result_store.latest("run_recovery_agent") is None;
    assert code(invoke("run_recovery_agent", {})) == "investigation_required";
}

test "session reads are copies and repository rejects older request writes" {
    first = AgentSession(simulation_run_id="r", facts={"scan_results": {"ids": ["A"]}});
    second = AgentSession(
        simulation_run_id="r", facts={"scan_results": {"ids": ["B"]}}
    );
    copied = first.read("scan_results");
    copied["ids"].append("INVENTED");
    assert first.read("scan_results")["ids"] == ["A"];
    assert second.tool_timeline == [];
    assert second.read("scan_results")["ids"] == ["B"];
    store = ResultStore();
    old = store.begin("scan", "payment", "r");
    latest = store.begin("scan", "payment", "r");
    assert not store.commit(
        "scan", "payment", "r", old, OperationEnvelope(status="completed")
    );
    assert store.commit(
        "scan", "payment", "r", latest, OperationEnvelope(status="completed")
    );
    store.sync("next");
    assert store.latest("scan", "payment") is None;
}


glob concurrent_barrier = Barrier(2),
     concurrent_sessions: list[AgentSession] = [];

def concurrent_assessment(session: AgentSession) -> OperationEnvelope {
    scan: OperationEnvelope = session.read("scan_results");
    impact: OperationEnvelope = session.read("impact");
    concurrent_sessions.append(session);
    concurrent_barrier.wait(timeout=5);
    assert scan.data["service_id"] == session.service_id;
    assert session.tool_timeline == ["scan_results", "impact"];
    return OperationEnvelope(
        status="completed",
        data={
            "simulation_run_id": session.simulation_run_id,
            "service_id": session.service_id,
            "findings": [
                {
                    "advisory_id": "ADV-1",
                    "package": "fixture",
                    "risk": "Review the cited advisory.",
                    "cited_advisory_ids": ["ADV-1"]
                }
            ],
            "dependents": impact.data["dependent_services"],
            "priority": "medium",
            "explanation": "Review the current package advisory."
        }
    );
}

def request_assessment(service_id: str) -> OperationEnvelope {
    return invoke("run_security_analysis", {"service_id": service_id});
}

test "concurrent analyst invocations keep independent session records" {
    mode = "completed";
    concurrent_barrier = Barrier(2);
    concurrent_sessions = [];
    ports = production_ports(AgentPorts(security=concurrent_assessment));
    ports.handlers["scan_service_dependencies"] = scan_fixture;
    configure_ports(ports);
    invoke("reset_incident", {});
    invoke("scan_service_dependencies", {"service_id": "payment"});
    invoke("scan_service_dependencies", {"service_id": "catalog"});
    with ThreadPoolExecutor(max_workers=2) as pool {
        first = pool.submit(request_assessment, "payment");
        second = pool.submit(request_assessment, "catalog");
        assert first.result(timeout=10).data["service_id"] == "payment";
        assert second.result(timeout=10).data["service_id"] == "catalog";
    }
    assert len(concurrent_sessions) == 2;
    assert concurrent_sessions[0] is not concurrent_sessions[1];
    assert concurrent_sessions[0].tool_timeline is not concurrent_sessions[
        1
    ].tool_timeline;
}

def rejected_agent(session: AgentSession) -> OperationEnvelope {
    return OperationEnvelope(
        status="failed",
        error=OperationError(
            code="provider_rate_limit", message="Offline rate-limit fixture."
        )
    );
}

test "agent-specific provider errors remain explicit and deterministic fallback survives" {
    setup();
    invoke("scan_service_dependencies", {"service_id": "payment"});
    invoke("run_investigation", {});
    configure_ports(
        production_ports(
            AgentPorts(
                security=rejected_agent,
                recovery=rejected_agent,
                repair_options=options_fixture,
                preview=preview_fixture
            )
        )
    );
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "provider_rate_limit";
    assert code(invoke("run_recovery_agent", {})) == "provider_rate_limit";
    assert invoke("analyze_security_impact", {"service_id": "payment"}).status == "completed";
    assert invoke("preview_recovery", {"service_id": "auth"}).status == "completed";
}


test "dependent compromise claims are rejected even with public display names" {
    setup();
    invoke("scan_service_dependencies", {"service_id": "payment"});
    mode = "unsafe_claim";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "unsupported_security_claim";
}


def empty_scan_response(service_id: str) -> OperationEnvelope {
    return OperationEnvelope(
        status="completed",
        data={
            "service_id": service_id,
            "inventory": [],
            "packages": [],
            "finding_count": 0
        }
    );
}

test "empty successful scan without package coverage cannot authorize an all-clear" {
    setup();
    ports = production_ports(AgentPorts(security=security_fixture));
    ports.handlers["scan_service_dependencies"] = empty_scan_response;
    configure_ports(ports);
    assert code(invoke("scan_service_dependencies", {"service_id": "payment"})) == "invalid_feature_response";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "scan_required";
}


test "newly accepted topology invalidates an in-flight assessment" {
    setup();
    invoke("scan_service_dependencies", {"service_id": "payment"});
    mode = "discover_during_analysis";
    assert code(invoke("run_security_analysis", {"service_id": "payment"})) == "stale_topology";
}
