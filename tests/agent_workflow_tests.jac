"""Production agent composition with real tools and MockLLM; no external requests."""
import from unittest.mock { patch }
import from concurrent.futures { ThreadPoolExecutor }
import from threading { Barrier }
import from jaclang.byllm.lib { MockLLM, MockToolCall, MockError, AuthenticationError }
import from contracts {
    AssessedFinding,
    Dependency,
    InvestigationResult,
    OperationEnvelope
}
import investigation.agent as investigator;
import security_analyst.agent as analyst;
import recovery_agent.agent as recoverer;
import security.osv as osv;
import security_analyst.tools as security_tools;
import recovery_agent.tools as recovery_tools;
import from security_analyst.tools { SecurityJudgment }
import from recovery_agent.tools { RecoveryChoice }
import from investigation.tools { trace_requests_tool }
import from integration.bindings { production_ports }
import from integration.gateway { invoke, read_dashboard }
import from integration.ports { configure_ports }
import from integration.result_store { result_store }
import from agent_support.claims { asserts_terms, asserts_clean_scan }
import from security_analyst.validation { validate_judgment, complete_findings }

# MockToolCall uses the marker's name, while the production function supplies its schema.
def finish_tool(final_output: any) -> any {
    return final_output;
}

def mock_model(outputs: list[any]) -> MockLLM {
    return MockLLM(model_name="mockllm", config={"outputs": outputs, "verbose": False});
}

def query_fixture(package: str, ecosystem: str, version: str) -> dict[str, any] {
    return {
        "vulns": [
            {
                "id": "GHSA-workflow",
                "summary": "Offline advisory",
                "database_specific": {"severity": "HIGH"},
                "references": [
                    {"type": "ADVISORY", "url": "https://example.test/advisory"}
                ]
            }
        ]
    };
}

def no_network(advisory_id: str) -> dict[str, any] {
    raise RuntimeError("Unexpected external detail request.");
}

def no_advisories(package: str, ecosystem: str, version: str) -> dict[str, any] {
    return {"vulns": []};
}

def failed_query(package: str, ecosystem: str, version: str) -> dict[str, any] {
    raise TimeoutError("Offline OSV timeout");
}

def judgment_for(package: str) -> SecurityJudgment {
    return SecurityJudgment(
        findings=[
            AssessedFinding(
                advisory_id="GHSA-workflow",
                package=package,
                risk="Review the cited exact-version advisory.",
                cited_advisory_ids=["GHSA-workflow"]
            )
        ],
        priority="low",
        explanation="Dependents may be operationally affected; there is no direct evidence they are vulnerable."
    );
}

def diagnosis_model(incident: str, run_id: str) -> MockLLM {
    links: list[Dependency] = [];
    origin = "auth" if incident == "auth_outage" else "payment";
    source = "payment" if origin == "auth" else "api_gateway";
    if origin == "auth" {
        links = [
            Dependency(
                source_id="payment",
                target_id="auth",
                kind="discovered",
                evidence_ids=[f"{run_id}-ev-1"]
            )
        ];
    }
    return mock_model(
        [
            MockToolCall(tool=trace_requests_tool, args={"service_id": source}),
            MockToolCall(
                tool=finish_tool,
                args={
                    "final_output": InvestigationResult(
                        status="completed",
                        candidate_root_causes=[f"{origin} unavailable"],
                        discovered_dependencies=links,
                        explanation="The cited request trace supports this candidate cause."
                    )
                }
            )
        ]
    );
}

def recovery_model_for(target: str, action: str, evidence_id: str) -> MockLLM {
    return mock_model(
        [
            MockToolCall(tool=recovery_tools.get_investigation_result_tool, args={}),
            MockToolCall(tool=recovery_tools.list_repair_options_tool, args={}),
            MockToolCall(
                tool=recovery_tools.preview_repair_tool,
                args={"service_id": target, "action": action}
            ),
            MockToolCall(
                tool=finish_tool,
                args={
                    "final_output": RecoveryChoice(
                        target_service_id=target,
                        action=action,
                        rationale="The cited trace supports previewing this target and action.",
                        cited_evidence_ids=[evidence_id]
                    )
                }
            )
        ]
    );
}

def code_of(result: OperationEnvelope) -> str {
    return result.error.code if result.error is not None else "";
}

test "production composition runs all three agents for both incidents with MockLLM" {
    configure_ports(production_ports());
    for (incident, target, action, package) in [
        ("auth_outage", "auth", "restart", "pyjwt"),
        ("payment_outage", "payment", "rollback", "jinja2")
    ] {
        invoke("start_incident", {"incident_id": incident});
        run_id = read_dashboard().simulation_run_id;
        before = [service.state for service in read_dashboard().services];
        with patch.object(
            investigator, "investigator_model", diagnosis_model(incident, run_id)
        ) {
            investigation = invoke("run_investigation", {});
        }
        assert investigation.status == "completed" , str(investigation.error);
        with patch.object(osv, "query_osv", query_fixture), patch.object(
            osv, "get_osv_advisory", no_network
        ) {
            scan = invoke("scan_service_dependencies", {"service_id": target});
        }
        assert scan.status == "completed";
        model = mock_model(
            [
                MockToolCall(tool=security_tools.get_scan_results_tool, args={}),
                MockToolCall(
                    tool=security_tools.get_impact_tool, args={"service_id": target}
                ),
                MockToolCall(tool=security_tools.get_known_dependencies_tool, args={}),
                MockToolCall(
                    tool=finish_tool, args={"final_output": judgment_for(package)}
                )
            ]
        );
        with patch.object(analyst, "analyst_model", model) {
            assessment = invoke("run_security_analysis", {"service_id": target});
        }
        assert assessment.status == "completed" , str(assessment.error);
        assert assessment.data["analysis_source"] == "model";
        assert assessment.data["priority_below_rule_based"];
        assert assessment.data["findings"][0]["cited_advisory_ids"] == [
            "GHSA-workflow"
        ];
        assert len(assessment.data["tool_timeline"]) == 3;
        evidence_id = investigation.data["evidence"][0]["id"];
        with patch.object(
            recoverer, "recovery_model", recovery_model_for(target, action, evidence_id)
        ) {
            proposal = invoke("run_recovery_agent", {});
        }
        assert proposal.status == "completed" , str(proposal.error);
        assert proposal.data["preview"]["outcome"] == "recovered";
        assert proposal.data["simulation_run_id"] == run_id;
        assert proposal.data["cited_evidence_ids"] == [evidence_id];
        assert before == [service.state for service in read_dashboard().services];
        with patch.object(
            recoverer,
            "recovery_model",
            recovery_model_for(target, "failover", evidence_id)
        ) {
            wrong = invoke("run_recovery_agent", {});
        }
        assert wrong.status == "completed"
        and wrong.data["preview"]["outcome"] == "not_recovered";
        for result in [assessment, proposal] {
            assert "root_fault" not in str(result.data)
            and "fault_kind" not in str(result.data)
            and "true_dependencies" not in str(result.data);
        }
        invoke("reset_incident", {});
        assert result_store.latest("run_security_analysis", target) is None;
        assert result_store.latest("run_recovery_agent") is None;
        assert code_of(invoke("run_recovery_agent", {})) == "investigation_required";
    }
}

def forbidden_judge(context: str, run_id: str) -> SecurityJudgment {
    raise AssertionError("A zero-advisory result must not invoke a model.");
}

test "production no-advisory path is deterministic and failed scans replace clean prerequisites" {
    configure_ports(production_ports());
    invoke("start_incident", {"incident_id": "auth_outage"});
    with patch.object(osv, "query_osv", no_advisories) {
        assert invoke("scan_service_dependencies", {"service_id": "auth"}).status == "completed";
    }
    with patch.object(analyst, "judge_security_impl", forbidden_judge) {
        assessment = invoke("run_security_analysis", {"service_id": "auth"});
    }
    assert assessment.status == "completed"
    and assessment.data["analysis_source"] == "deterministic";
    with patch.object(osv, "query_osv", failed_query) {
        assert invoke("scan_service_dependencies", {"service_id": "auth"}).status == "failed";
    }
    assert code_of(invoke("run_security_analysis", {"service_id": "auth"})) == "scan_failed";
}

def session_scan(service_id: str, run_id: str) -> OperationEnvelope {
    return OperationEnvelope(
        status="completed",
        data={
            "service_id": service_id,
            "simulation_run_id": run_id,
            "finding_count": 1,
            "packages": [
                {
                    "package": service_id,
                    "findings": [
                        {
                            "advisory_id": "GHSA-workflow",
                            "package": service_id,
                            "summary": "Offline"
                        }
                    ]
                }
            ]
        }
    );
}

test "real analyst tool sessions remain isolated under concurrent execution and clean up" {
    invoke("start_incident", {"incident_id": "auth_outage"});
    run_id = read_dashboard().simulation_run_id;
    gate = Barrier(2);
    def judge(context: str, active_run: str) -> SecurityJudgment {
        scan = security_tools.get_scan_results_tool();
        gate.wait(timeout=10);
        again = security_tools.get_scan_results_tool();
        assert scan == again;
        return judgment_for(scan["service_id"]);
    }
    def run(service_id: str) -> OperationEnvelope {
        result = analyst.run_security_analysis_with(
            judge, service_id, session_scan(service_id, run_id), run_id
        );
        assert security_tools.active_session.get() is None;
        return result;
    }
    with ThreadPoolExecutor(max_workers=2) as pool {
        auth = pool.submit(run, "auth");
        payment = pool.submit(run, "payment");
        for result in [auth.result(timeout=15), payment.result(timeout=15)] {
            assert result.status == "completed" , str(result.error);
            assert result.data["findings"][0]["package"] == result.data["service_id"];
            assert result.data["tool_timeline"] == [
                "get_scan_results()",
                "get_scan_results()"
            ];
        }
    }
}

test "real recovery tool sessions keep separate investigation records under concurrent execution" {
    invoke("start_incident", {"incident_id": "auth_outage"});
    run_id = read_dashboard().simulation_run_id;
    gate = Barrier(2);
    def choose(context: str, active_run: str) -> RecoveryChoice {
        record = recovery_tools.get_investigation_result_tool();
        gate.wait(timeout=10);
        assert record == recovery_tools.get_investigation_result_tool();
        return RecoveryChoice(
            target_service_id="auth",
            action="restart",
            rationale="Preview the cited observation.",
            cited_evidence_ids=[record["evidence"][0]["id"]]
        );
    }
    def run(evidence_id: str) -> OperationEnvelope {
        data = {
            "simulation_run_id": run_id,
            "evidence": [{"id": evidence_id, "simulation_run_id": run_id}]
        };
        result = recoverer.run_recovery_with(choose, data, run_id);
        assert recovery_tools.active_session.get() is None;
        return result;
    }
    with ThreadPoolExecutor(max_workers=2) as pool {
        first = pool.submit(run, "first");
        second = pool.submit(run, "second");
        for (future, expected) in [(first, "first"), (second, "second")] {
            result = future.result(timeout=15);
            assert result.status == "completed" , str(result.error);
            assert result.data["cited_evidence_ids"] == [expected];
            assert len(result.data["tool_timeline"]) == 2;
        }
    }
}

test "swallowed tool errors cannot become successful agent results" {
    invoke("start_incident", {"incident_id": "auth_outage"});
    run_id = read_dashboard().simulation_run_id;
    def judge(context: str, active_run: str) -> SecurityJudgment {
        try {
            security_tools.get_impact_tool("unknown");
        } except RuntimeError { }
        return judgment_for("auth");
    }
    result = analyst.run_security_analysis_with(
        judge, "auth", session_scan("auth", run_id), run_id
    );
    assert code_of(result) == "security_agent_tool_error";
    def choose(context: str, active_run: str) -> RecoveryChoice {
        try {
            recovery_tools.preview_repair_tool("auth", "unknown");
        } except RuntimeError { }
        return RecoveryChoice(
            target_service_id="auth",
            action="restart",
            rationale="Attempted preview.",
            cited_evidence_ids=["ev"]
        );
    }
    result = recoverer.run_recovery_with(
        choose,
        {
            "simulation_run_id": run_id,
            "evidence": [{"id": "ev", "simulation_run_id": run_id}]
        },
        run_id
    );
    assert code_of(result) == "recovery_agent_tool_error";
}

test "claim guards allow disclaimers and reject contradictory affirmative clauses" {
    assert not asserts_terms(
        "There is no direct evidence they are vulnerable.", ["vulnerable"]
    );
    assert not asserts_terms("Dependents are not compromised.", ["compromised"]);
    assert asserts_terms(
        "No evidence exists; however Payment is compromised.", ["compromised"]
    );
    assert asserts_terms(
        "Payment is compromised but not confirmed compromised.", ["compromised"]
    );
    assert not asserts_clean_scan("This is not an all-clear: some lookups failed.");
    assert asserts_clean_scan("This is not an all-clear; however all clear now.");
}

test "one advisory affecting multiple packages retains both package assessments" {
    scan = {
        "packages": [
            {"package": "first", "findings": [{"advisory_id": "GHSA-workflow"}]},
            {"package": "second", "findings": [{"advisory_id": "GHSA-workflow"}]}
        ]
    };
    judgment = judgment_for("first");
    assert validate_judgment(judgment, scan) is None;
    findings = complete_findings(judgment, scan);
    assert [finding.package for finding in findings] == ["first", "second"];
    assert findings[0].risk == judgment.findings[0].risk;
    assert "Not assessed by the model" in findings[1].risk;
}

test "real feature failures preserve provider codes through the production adapter" {
    configure_ports(production_ports());
    invoke("start_incident", {"incident_id": "auth_outage"});
    with patch.object(osv, "query_osv", query_fixture), patch.object(
        osv, "get_osv_advisory", no_network
    ) {
        invoke("scan_service_dependencies", {"service_id": "auth"});
    }
    model = mock_model(
        [MockError(error=AuthenticationError("Offline credential rejection"))]
    );
    with patch.object(analyst, "analyst_model", model) {
        result = invoke("run_security_analysis", {"service_id": "auth"});
    }
    assert code_of(result) == "security_analyst_authentication_error" , str(
        result.error
    );
    assert invoke("analyze_security_impact", {"service_id": "auth"}).status == "completed";
    run_id = read_dashboard().simulation_run_id;
    with patch.object(
        investigator, "investigator_model", diagnosis_model("auth_outage", run_id)
    ) {
        invoke("run_investigation", {});
    }
    model = mock_model(
        [MockError(error=AuthenticationError("Offline credential rejection"))]
    );
    with patch.object(recoverer, "recovery_model", model) {
        result = invoke("run_recovery_agent", {});
    }
    assert code_of(result) == "recovery_agent_authentication_error";
}

test "real analyst handles partial no-findings scans without an all-clear or model call" {
    configure_ports(production_ports());
    invoke("start_incident", {"incident_id": "auth_outage"});
    ports = production_ports();
    def partial_scan(service_id: str) -> OperationEnvelope {
        return OperationEnvelope(
            status="partial",
            data={
                "service_id": service_id,
                "inventory": [],
                "packages": [{"name": "pyjwt", "status": "failed", "advisories": []}],
                "finding_count": 0
            }
        );
    }
    ports.handlers["scan_service_dependencies"] = partial_scan;
    configure_ports(ports);
    assert invoke("scan_service_dependencies", {"service_id": "auth"}).status == "partial";
    with patch.object(analyst, "judge_security_impl", forbidden_judge) {
        assessment = invoke("run_security_analysis", {"service_id": "auth"});
    }
    assert assessment.status == "partial" , str(assessment.error);
    assert code_of(assessment) == "scan_incomplete";
    assert assessment.data["analysis_source"] == "deterministic";
    assert "not an all-clear" in str(assessment.data["explanation"]);
}

test "real recovery reports no active incident before calling a chooser" {
    invoke("reset_incident", {});
    run_id = read_dashboard().simulation_run_id;
    def forbidden_chooser(context: str, active_run: str) -> RecoveryChoice {
        raise AssertionError("No incident needs no model.");
    }
    result = recoverer.run_recovery_with(
        forbidden_chooser,
        {
            "simulation_run_id": run_id,
            "evidence": [{"id": "ev", "simulation_run_id": run_id}]
        },
        run_id
    );
    assert code_of(result) == "no_active_incident";
}
