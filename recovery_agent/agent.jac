"""Bounded Recovery agent: proposes a repair that the simulator then verifies."""

import json;
import from dataclasses { asdict }
import from catalog { documented_dependencies }
import from contracts { OperationEnvelope }
import from agent_support.models {
    agent_failure,
    envelope_for_model_error,
    make_agent_model
}
import from simulation.recovery { sim_list_repair_options, sim_preview_repair }
import from integration.run_context { current_dashboard, is_current_run }
import from .tools {
    RecoveryChoice,
    begin_recovery_session,
    end_recovery_session,
    recovery_tool_errors,
    get_impact_tool,
    get_investigation_result_tool,
    known_service_ids,
    list_repair_options_tool,
    preview_repair_tool,
    recovery_tool_timeline,
}
import from .validation { build_proposal, proposal_to_dict, validate_recovery_choice, }

glob recovery_model = make_agent_model();

def choose_recovery_impl(incident_context: str, active_run_id: str,) -> RecoveryChoice by recovery_model(
    tools=[
        list_repair_options_tool,
        get_investigation_result_tool,
        get_impact_tool,
        preview_repair_tool,

    ],
    temperature=0.2,
    max_tokens=900,
    max_react_iterations=6,
    max_output_retries=1,
);

sem choose_recovery_impl = "Choose one repair for the active incident. Read the Investigator result first, list the repair options, and preview before you commit. Cite only evidence IDs from the Investigator result. Never invent evidence, causes, or preview outcomes.";
sem choose_recovery_impl.incident_context = "Documented topology and visible service states only. It excludes the private graph and the injected fault.";
sem choose_recovery_impl.active_run_id = "The current simulation run ID. Anything from another run is stale.";

def _incident_context -> str {
    snapshot = current_dashboard();
    return json.dumps(
        {
            "services": [asdict(service) for service in snapshot.services],
            "documented_dependencies": [
                asdict(link) for link in documented_dependencies()
            ],

        }
    );
}

def _incident_is_active -> bool {
    for service in current_dashboard().services {
        if service.state != "healthy" {
            return True;
        }
    }
    return False;
}

def run_recovery_with(
    chooser: Callable[[str, str], RecoveryChoice],
    investigation: dict[str, any],
    run_id: str,
) -> OperationEnvelope {
    if not investigation {
        return agent_failure(
            "investigation_required",
            "Run the investigation before asking for a recovery proposal."
        );
    }
    if not is_current_run(run_id) {
        return agent_failure("stale_run", "The simulation changed. Run it again.");
    }
    if not _incident_is_active() {
        return agent_failure(
            "no_active_incident",
            "No incident is active, so there is nothing to recover."
        );
    }
    token = begin_recovery_session(run_id, investigation);
    try {
        choice = chooser(_incident_context(), run_id);
        if recovery_tool_errors() {
            return agent_failure(
                "recovery_agent_tool_error",
                "A read-only diagnostic tool failed during this session."
            );
        }
        if not is_current_run(run_id) {
            return agent_failure(
                "stale_run", "The simulation changed during the recovery analysis."
            );
        }
        actions = [
            item["action"] for item in sim_list_repair_options().data["options"]
        ];
        problem = validate_recovery_choice(
            choice, investigation, run_id, known_service_ids(), actions
        );
        if problem is not None {
            return agent_failure(problem.code, problem.message);
        }
        preview = sim_preview_repair(choice.target_service_id, choice.action);
        if preview.status != "completed" {
            return preview;
        }
        proposal = build_proposal(choice, run_id, preview.data);
        return OperationEnvelope(
            status="completed",
            data=proposal_to_dict(proposal, recovery_tool_timeline()),
        );
    } except Exception as error {
        return envelope_for_model_error("recovery_agent", error);
    } finally {
        end_recovery_session(token);
    }
}


def run_recovery_agent_impl(
    investigation: dict[str, any], run_id: str
) -> OperationEnvelope {
    return run_recovery_with(choose_recovery_impl, investigation, run_id);
}
