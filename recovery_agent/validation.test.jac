"""Recovery choice validation: citations, catalog membership, and stale runs."""

import from .tools { RecoveryChoice }

glob SERVICES = [
         "frontend",
         "api_gateway",
         "payment",
         "catalog",
         "auth",
         "database"
     ];
glob ACTIONS = ["restart", "rollback", "failover"];

def investigation_for(run_id: str) -> dict[str, any] {
    return {
        "simulation_run_id": run_id,
        "evidence": [
            {
                "id": "ev-1",
                "tool": "check_service_health",
                "service_id": "auth",
                "observation": {"state": "down"},
                "simulation_run_id": run_id,

            },
            {
                "id": "ev-old",
                "tool": "check_service_health",
                "service_id": "auth",
                "observation": {"state": "down"},
                "simulation_run_id": "run-0",

            },

        ],

    };
}

def choice_with(
    target: str = "auth",
    action: str = "restart",
    rationale: str = "Auth is down.",
    cited: list[str] = ["ev-1"],
) -> RecoveryChoice {
    return RecoveryChoice(
        target_service_id=target,
        action=action,
        rationale=rationale,
        cited_evidence_ids=cited,
    );
}

def problem_code(choice: RecoveryChoice, run_id: str = "run-1") -> str {
    problem = validate_recovery_choice(
        choice, investigation_for("run-1"), run_id, SERVICES, ACTIONS
    );
    return problem.code if problem is not None else "";
}

test "a cited, listed choice is accepted" {
    assert problem_code(choice_with()) == "";
}

test "unknown target or action is rejected" {
    assert problem_code(choice_with(target="billing")) == "unknown_service";
    assert problem_code(choice_with(action="reboot")) == "unknown_repair_action";
}

test "citations are required and must belong to the current investigation" {
    assert problem_code(choice_with(cited=[])) == "missing_citation";
    assert problem_code(choice_with(cited=["ev-404"])) == "unsupported_citation";
    assert problem_code(choice_with(cited=["ev-old"])) == "unsupported_citation";
    assert problem_code(choice_with(rationale="  ")) == "missing_rationale";
}

test "an investigation from another run is stale" {
    assert problem_code(choice_with(), run_id="run-2") == "stale_investigation";
}

test "the preview decides the outcome, not the model" {
    preview = {
        "before": [{"id": "auth", "state": "down"}],
        "after": [{"id": "auth", "state": "down"}],
        "outcome": "not_recovered",

    };
    proposal = build_proposal(
        choice_with(rationale="It will surely work."), "run-1", preview
    );
    assert proposal.preview.outcome == "not_recovered";
    data = proposal_to_dict(proposal, ["list_repair_options()"]);
    assert data["preview"]["outcome"] == "not_recovered";
    assert data["tool_timeline"] == ["list_repair_options()"];
}
