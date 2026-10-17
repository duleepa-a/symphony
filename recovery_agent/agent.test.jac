"""Recovery agent behavior on the real simulator with MockLLM and fixed choosers.

No test calls Gemini. Choosers are plain functions or MockLLM-driven tool loops.
"""

import from jaclang.byllm.lib { MockLLM, MockToolCall }
import from contracts { OperationEnvelope }
import from simulation.state { sim_start_incident, sim_reset, sim_dashboard_state }
import from simulation.diagnostics { sim_check_health }
import from .tools {
    RecoveryChoice,
    get_investigation_result_tool,
    list_repair_options_tool,
    preview_repair_tool,
}

def investigation_for_run(run_id: str, origin: str) -> dict[str, any] {
    return {
        "simulation_run_id": run_id,
        "candidate_root_causes": [origin],
        "discovered_dependencies": [],
        "explanation": f"{origin} is the likely origin.",
        "evidence": [
            {
                "id": "mock-ev-1",
                "tool": "check_service_health",
                "service_id": origin,
                "observation": {"state": "down"},
                "simulation_run_id": run_id,

            }
        ],

    };
}

def start(incident: str, origin: str) -> dict[str, any] {
    run_id = sim_start_incident(incident).data["simulation_run_id"];
    return investigation_for_run(run_id, origin);
}

def fixed_chooser(
    target: str, action: str, cited: list[str] = ["mock-ev-1"]
) -> Callable[[str, str], RecoveryChoice] {
    def choose(context: str, run_id: str) -> RecoveryChoice {
        return RecoveryChoice(
            target_service_id=target,
            action=action,
            rationale="Chosen from the investigation.",
            cited_evidence_ids=cited,
        );
    }
    return choose;
}

def code_of(result: OperationEnvelope) -> str {
    return result.error.code if result.error is not None else "";
}

def exploding_chooser(context: str, run_id: str) -> RecoveryChoice {
    raise RuntimeError("provider exploded");
}

def finish_tool(final_output: RecoveryChoice) -> RecoveryChoice {
    return final_output;
}

glob mock_recoverer = MockLLM(
         model_name="mockllm",
         config={
             "outputs": [
                 MockToolCall(tool=get_investigation_result_tool, args={},),
                 MockToolCall(tool=list_repair_options_tool, args={},),
                 MockToolCall(
                     tool=preview_repair_tool,
                     args={"service_id": "auth", "action": "restart"},
                 ),
                 MockToolCall(
                     tool=finish_tool,
                     args={
                         "final_output": RecoveryChoice(
                             target_service_id="auth",
                             action="restart",
                             rationale="Auth is down and the restart preview recovered it.",
                             cited_evidence_ids=["mock-ev-1"],
                         )
                     },
                 ),

             ],
             "verbose": False,

         },
     );

def _mock_choose(incident_context: str, active_run_id: str,) -> RecoveryChoice by mock_recoverer(
    tools=[
        get_investigation_result_tool,
        list_repair_options_tool,
        preview_repair_tool
    ],
    max_react_iterations=6,
    max_output_retries=1,
);

sem _mock_choose = "Choose a repair using the supplied tools.";
sem _mock_choose.incident_context = "Visible service states.";
sem _mock_choose.active_run_id = "Current run ID.";

test "MockLLM tool loop yields a verified recovered proposal for the auth outage" {
    investigation = start("auth_outage", "auth");
    result = run_recovery_with(
        _mock_choose, investigation, investigation["simulation_run_id"]
    );
    assert result.status == "completed";
    assert result.data["target_service_id"] == "auth";
    assert result.data["preview"]["outcome"] == "recovered";
    assert result.data["tool_timeline"] == [
        "get_investigation_result()",
        "list_repair_options()",
        "preview_repair(auth, restart)",

    ];
    assert len(mock_recoverer.seen_prompts) >= 1;
}

test "the active incident is not mutated by a proposal" {
    investigation = start("payment_outage", "payment");
    run_id = investigation["simulation_run_id"];
    result = run_recovery_with(
        fixed_chooser("payment", "rollback"), investigation, run_id
    );
    assert result.data["preview"]["outcome"] == "recovered";
    states = {s.id: s.state for s in sim_dashboard_state().services};
    assert states["payment"] == "down" and states["frontend"] == "down";
}

test "a wrong action or target is reported as not recovered" {
    investigation = start("auth_outage", "auth");
    run_id = investigation["simulation_run_id"];
    wrong_action = run_recovery_with(
        fixed_chooser("auth", "failover"), investigation, run_id
    );
    wrong_target = run_recovery_with(
        fixed_chooser("payment", "restart"), investigation, run_id
    );
    assert wrong_action.status == "completed";
    assert wrong_action.data["preview"]["outcome"] == "not_recovered";
    assert wrong_target.data["preview"]["outcome"] == "not_recovered";
}

test "uncited, unknown, or invented choices fail instead of succeeding" {
    investigation = start("auth_outage", "auth");
    run_id = investigation["simulation_run_id"];
    uncited = run_recovery_with(
        fixed_chooser("auth", "restart", []), investigation, run_id
    );
    invented = run_recovery_with(
        fixed_chooser("auth", "restart", ["made-up"]), investigation, run_id
    );
    bad_action = run_recovery_with(
        fixed_chooser("auth", "reboot"), investigation, run_id
    );
    assert uncited.status == "failed" and code_of(uncited) == "missing_citation";
    assert code_of(invented) == "unsupported_citation";
    assert code_of(bad_action) == "unknown_repair_action";
}

test "prerequisites are explicit failures" {
    assert code_of(run_recovery_with(fixed_chooser("auth", "restart"), {}, "run-x")) == "investigation_required";
    investigation = start("auth_outage", "auth");
    old_run = investigation["simulation_run_id"];
    sim_start_incident("auth_outage");
    stale = run_recovery_with(fixed_chooser("auth", "restart"), investigation, old_run);
    assert code_of(stale) == "stale_run";
    sim_reset();
    current = sim_dashboard_state().simulation_run_id;
    healthy = run_recovery_with(
        fixed_chooser("auth", "restart"),
        investigation_for_run(current, "auth"),
        current
    );
    assert code_of(healthy) == "no_active_incident";
}

test "an investigation from an earlier run is rejected" {
    investigation = start("auth_outage", "auth");
    current = sim_start_incident("auth_outage").data["simulation_run_id"];
    result = run_recovery_with(
        fixed_chooser("auth", "restart"), investigation, current
    );
    assert result.status == "failed" and code_of(result) == "stale_investigation";
}

test "provider and tool errors become failed results" {
    investigation = start("auth_outage", "auth");
    result = run_recovery_with(
        exploding_chooser, investigation, investigation["simulation_run_id"]
    );
    assert result.status == "failed";
    assert code_of(result) == "recovery_agent_tool_or_provider_error";
}

test "the injected fault never appears in tool output" {
    investigation = start("payment_outage", "payment");
    run_id = investigation["simulation_run_id"];
    result = run_recovery_with(
        fixed_chooser("payment", "rollback"), investigation, run_id
    );
    text = str(result.data);
    assert "bad_release" not in text and "crashed_process" not in text;
    assert "root_fault" not in text and "fault_kind" not in text;
}
