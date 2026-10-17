"""Validate a Recovery choice against the current investigation and repair catalog."""

import from contracts { OperationError, RecoveryProposal, RepairPreview }
import from .tools { RecoveryChoice }

def _error(code: str, message: str) -> OperationError {
    return OperationError(code=code, message=message);
}

def validate_recovery_choice(
    choice: RecoveryChoice,
    investigation: dict[str, any],
    run_id: str,
    service_ids: list[str],
    actions: list[str],
) -> OperationError | None {
    if investigation.get("simulation_run_id", "") != run_id {
        return _error(
            "stale_investigation",
            "The Investigator result belongs to a different simulation run."
        );
    }
    if choice.target_service_id not in service_ids {
        return _error(
            "unknown_service", f"Unknown target service '{choice.target_service_id}'."
        );
    }
    if choice.action not in actions {
        return _error(
            "unknown_repair_action",
            f"Action '{choice.action}' is not one of the listed repair options."
        );
    }
    if not choice.rationale.strip() {
        return _error("missing_rationale", "The proposal has no rationale.");
    }
    if len(choice.cited_evidence_ids) == 0 {
        return _error(
            "missing_citation", "The proposal must cite investigation evidence."
        );
    }
    valid_ids = [
        item.get("id", "")
        for item in investigation.get("evidence", [])
        if item.get("simulation_run_id", "") == run_id
    ];
    for evidence_id in choice.cited_evidence_ids {
        if evidence_id not in valid_ids {
            return _error(
                "unsupported_citation",
                f"Evidence '{evidence_id}' is not part of the current investigation."
            );
        }
    }
    return None;
}

def build_proposal(
    choice: RecoveryChoice, run_id: str, preview: dict[str, any]
) -> RecoveryProposal {
    # The outcome comes from the simulator preview, never from the model.
    return RecoveryProposal(
        simulation_run_id=run_id,
        target_service_id=choice.target_service_id,
        action=choice.action,
        rationale=choice.rationale,
        cited_evidence_ids=choice.cited_evidence_ids,
        preview=RepairPreview(
            before=preview["before"], after=preview["after"], outcome=preview["outcome"]
        ),
    );
}

def proposal_to_dict(
    proposal: RecoveryProposal, tool_timeline: list[str]
) -> dict[str, any] {
    return {
        "simulation_run_id": proposal.simulation_run_id,
        "target_service_id": proposal.target_service_id,
        "action": proposal.action,
        "rationale": proposal.rationale,
        "cited_evidence_ids": proposal.cited_evidence_ids,
        "preview": {
            "before": proposal.preview.before,
            "after": proposal.preview.after,
            "outcome": proposal.preview.outcome,

        },
        "tool_timeline": tool_timeline,

    };
}
