"""MockLLM coverage for the bounded diagnostic tool loop."""

import from jaclang.byllm.lib { MockLLM, MockToolCall }
import from contracts { Dependency, Evidence, InvestigationResult }
import from .fixtures {
    completed_investigation_fixture,
    failed_investigation_fixture,
    stale_evidence_fixture,
}
import from .tools {
    configure_diagnostic_tools,
    investigation_evidence,
    investigation_tool_timeline,
    prepare_diagnostic_run,
    trace_requests_tool,
    use_fixture_diagnostic_tools,
}
import from .validation { validate_investigation_result }

def _injected_health(service_id: str) -> Evidence {
    return Evidence(
        id=f"injected-health-{service_id}",
        tool="check_service_health",
        service_id=service_id,
        observation={"state": "healthy"},
        simulation_run_id="injected-run",
    );
}

def _injected_logs(service_id: str) -> Evidence {
    return Evidence(
        id=f"injected-logs-{service_id}",
        tool="get_service_logs",
        service_id=service_id,
        observation={"message": "injected"},
        simulation_run_id="injected-run",
    );
}

def _injected_traces(service_id: str) -> Evidence {
    return Evidence(
        id=f"injected-trace-{service_id}",
        tool="trace_requests",
        service_id=service_id,
        observation={"source_id": service_id, "target_id": "auth"},
        simulation_run_id="injected-run",
    );
}

def finish_tool(final_output: InvestigationResult) -> InvestigationResult {
    return final_output;
}

glob mock_investigator = MockLLM(
         model_name="mockllm",
         config={
             "outputs": [
             MockToolCall(tool=trace_requests_tool, args={"service_id": "payment"},),
             MockToolCall(
                 tool=finish_tool,
                 args={
                     "final_output": InvestigationResult(
                         status="completed",
                         candidate_root_causes=[
                             "Auth outage interrupts checkout token validation"
                         ],
                         discovered_dependencies=[
                             Dependency(
                                 source_id="payment",
                                 target_id="auth",
                                 kind="discovered",
                                 evidence_ids=["trace_requests-payment-1"],
                             )
                         ],
                         explanation="The Payment trace records a failed Auth token-validation call.",
                     )
                 },
             ),

             ],
             "verbose": False,
         },
     );

def _mock_investigate(
    incident_context: str, active_run_id: str,
) -> InvestigationResult by mock_investigator(
    tools=[trace_requests_tool], max_react_iterations=6, max_output_retries=1,
);

sem _mock_investigate = "Investigate only through the supplied diagnostic tool and return evidence-backed conclusions.";
sem _mock_investigate.incident_context = "Documented topology and visible service state.";
sem _mock_investigate.active_run_id = "Current simulation run identifier.";

test "MockLLM records real tool call and validates discovered edge" {
    use_fixture_diagnostic_tools();
    prepare_diagnostic_run("mock-run");
    model_result = _mock_investigate(
        "Auth, Payment, API Gateway, and Frontend are down.", "mock-run",
    );
    result = validate_investigation_result(
        model_result,
        investigation_tool_timeline(),
        investigation_evidence(),
        "mock-run",
    );
    assert result.status == "completed";
    assert result.tool_timeline == ["trace_requests(payment)"];
    assert len(result.observed_evidence) == 1;
    assert len(result.discovered_dependencies) == 1;
    assert result.discovered_dependencies[0].target_id == "auth";
    assert len(mock_investigator.seen_prompts) >= 1;
}

test "handoff fixtures cover completed failed and stale states" {
    assert completed_investigation_fixture().status == "completed";
    assert failed_investigation_fixture().status == "failed";
    assert stale_evidence_fixture()[0].simulation_run_id == "previous-run";
}

test "integration can inject real diagnostic providers" {
    configure_diagnostic_tools(_injected_health, _injected_logs, _injected_traces);
    prepare_diagnostic_run("injected-run");
    evidence = trace_requests_tool("payment");
    assert evidence.id == "injected-trace-payment";
    assert investigation_tool_timeline() == ["trace_requests(payment)"];
    assert investigation_evidence()[0].simulation_run_id == "injected-run";
}
