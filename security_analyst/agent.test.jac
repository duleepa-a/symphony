"""Security Analyst behavior on the real simulator with MockLLM and fixed judges.

No test calls Gemini or OSV.
"""

import from jaclang.byllm.lib { MockLLM, MockToolCall }
import from contracts { AssessedFinding, OperationEnvelope }
import from simulation.state {
    sim_start_incident,
    sim_reset,
    sim_dashboard_state,
    sim_accept_discovered_dependency
}
import from simulation.diagnostics { sim_trace_requests }
import from .fixtures { fixture_scan }
import from .tools {
    SecurityJudgment,
    get_impact_tool,
    get_known_dependencies_tool,
    get_scan_results_tool,
}

def code_of(result: OperationEnvelope) -> str {
    return result.error.code if result.error is not None else "";
}

def scan_for(case_name: str, run_id: str) -> OperationEnvelope {
    scan = fixture_scan(case_name);
    scan.data["simulation_run_id"] = run_id;
    return scan;
}

def start_run -> str {
    return sim_start_incident("auth_outage").data["simulation_run_id"];
}

def good_judgment(priority: str = "high") -> SecurityJudgment {
    return SecurityJudgment(
        findings=[
            AssessedFinding(
                advisory_id="GHSA-fixture-0001",
                package="pyjwt",
                risk="Severity is unknown, so the risk to token validation is unconfirmed.",
                cited_advisory_ids=["GHSA-fixture-0001"],
            )
        ],
        priority=priority,
        explanation="One advisory affects Auth. Dependents may be operationally affected; there is no direct evidence they are vulnerable.",
    );
}

def fixed_judge(judgment: SecurityJudgment) -> Callable[[str, str], SecurityJudgment] {
    def judge(context: str, run_id: str) -> SecurityJudgment {
        return judgment;
    }
    return judge;
}

def exploding_judge(context: str, run_id: str) -> SecurityJudgment {
    raise RuntimeError("provider exploded");
}

def never_called(context: str, run_id: str) -> SecurityJudgment {
    raise RuntimeError("the model must not be called for this case");
}

def finish_tool(final_output: SecurityJudgment) -> SecurityJudgment {
    return final_output;
}

glob mock_analyst = MockLLM(
         model_name="mockllm",
         config={
             "outputs": [
                 MockToolCall(tool=get_scan_results_tool, args={},),
                 MockToolCall(tool=get_impact_tool, args={"service_id": "auth"},),
                 MockToolCall(tool=get_known_dependencies_tool, args={},),
                 MockToolCall(
                     tool=finish_tool,
                     args={
                         "final_output": SecurityJudgment(
                             findings=[
                                 AssessedFinding(
                                     advisory_id="GHSA-fixture-0001",
                                     package="pyjwt",
                                     risk="Unconfirmed risk to token validation.",
                                     cited_advisory_ids=["GHSA-fixture-0001"],
                                 )
                             ],
                             priority="high",
                             explanation="One advisory affects Auth; dependents are potentially affected.",
                         )
                     },
                 ),

             ],
             "verbose": False,

         },
     );

def _mock_judge(incident_context: str, active_run_id: str,) -> SecurityJudgment by mock_analyst(
    tools=[get_scan_results_tool, get_impact_tool, get_known_dependencies_tool],
    max_react_iterations=6,
    max_output_retries=1,
);

sem _mock_judge = "Assess the scanned service using the supplied tools.";
sem _mock_judge.incident_context = "Service and scan status.";
sem _mock_judge.active_run_id = "Current run ID.";

test "MockLLM tool loop yields a cited assessment with rule-based facts attached" {
    sim_reset();
    run_id = sim_start_incident("normal").data["simulation_run_id"];
    result = run_security_analysis_with(
        _mock_judge, "auth", scan_for("findings", run_id), run_id
    );
    assert result.status == "completed" , str(result.error);
    assert result.data["findings"][0]["advisory_id"] == "GHSA-fixture-0001";
    assert result.data["tool_timeline"] == [
        "get_scan_results()",
        "get_impact(auth)",
        "get_known_dependencies()",

    ];
    assert result.data["rule_based_priority"] == "low";
    assert len(mock_analyst.seen_prompts) >= 1;
}

test "a failed or missing scan never becomes a clean assessment" {
    run_id = start_run();
    failed = run_security_analysis_with(
        never_called, "auth", scan_for("failed", run_id), run_id
    );
    assert failed.status == "failed" and code_of(failed) == "scan_unavailable";
    empty = OperationEnvelope(status="completed");
    assert code_of(run_security_analysis_with(never_called, "auth", empty, run_id)) == "scan_unavailable";
}

test "a completed scan with no advisories needs no model call" {
    run_id = start_run();
    result = run_security_analysis_with(
        never_called, "auth", scan_for("none", run_id), run_id
    );
    assert result.status == "completed" , str(result.error);
    assert result.data["findings"] == [] and result.data["finding_count"] == 0;
    assert "only the listed packages" in str(result.data["explanation"]);
}

test "a partial scan is reported as partial and is not an all-clear" {
    run_id = start_run();
    with_finding = run_security_analysis_with(
        fixed_judge(good_judgment()), "auth", scan_for("partial", run_id), run_id
    );
    assert with_finding.status == "partial";
    assert with_finding.data["scan_status"] == "partial";
    assert len(with_finding.data["findings"]) == 1;
    partial_empty = scan_for("partial", run_id);
    partial_empty.data["packages"][0]["findings"] = [];
    result = run_security_analysis_with(never_called, "auth", partial_empty, run_id);
    assert result.status == "partial";
    assert "not an all-clear" in str(result.data["explanation"]);
}

test "invented advisories and overstated impact fail validation" {
    run_id = start_run();
    invented = good_judgment();
    invented.findings[0].advisory_id = "GHSA-invented";
    assert code_of(
        run_security_analysis_with(
            fixed_judge(invented), "auth", scan_for("findings", run_id), run_id
        )
    ) == "unsupported_advisory";
    overstated = good_judgment();
    overstated.explanation = "Payment is compromised.";
    assert code_of(
        run_security_analysis_with(
            fixed_judge(overstated), "auth", scan_for("findings", run_id), run_id
        )
    ) == "overstated_impact";
}

test "a lower model priority is returned beside the rule-based one" {
    run_id = start_run();
    result = run_security_analysis_with(
        fixed_judge(good_judgment("low")), "auth", scan_for("findings", run_id), run_id
    );
    assert result.data["priority"] == "low";
    assert result.data["rule_based_priority"] == "low";
    sim_start_incident("auth_outage");
}

test "stale runs, wrong services, and other-run scans are rejected" {
    old_run = start_run();
    run_id = sim_start_incident("auth_outage").data["simulation_run_id"];
    assert code_of(
        run_security_analysis_with(
            never_called, "auth", fixture_scan("findings"), old_run
        )
    ) == "stale_run";
    assert code_of(
        run_security_analysis_with(
            never_called, "payment", scan_for("findings", run_id), run_id
        )
    ) == "scan_service_mismatch";
    assert code_of(
        run_security_analysis_with(
            never_called, "auth", fixture_scan("findings"), run_id
        )
    ) == "stale_scan";
}

test "provider errors become failed results" {
    run_id = start_run();
    result = run_security_analysis_with(
        exploding_judge, "auth", scan_for("findings", run_id), run_id
    );
    assert result.status == "failed";
    assert code_of(result) == "security_analyst_tool_or_provider_error";
    states = {s.id: s.state for s in sim_dashboard_state().services};
    assert states["auth"] == "down";
}
