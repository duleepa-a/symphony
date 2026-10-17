"""Validate model output against diagnostic evidence actually observed."""

import from contracts { Dependency, Evidence, InvestigationResult }

import from integration.evidence { supports_dependency }

def validate_investigation_result(
    model_result: InvestigationResult,
    actual_timeline: list[str],
    actual_evidence: list[Evidence],
    active_run_id: str,
) -> InvestigationResult {
    current_evidence = [
        item
        for item in actual_evidence
        if item.simulation_run_id == active_run_id
    ];
    accepted_dependencies = [
        item
        for item in model_result.discovered_dependencies
        if supports_dependency(item, current_evidence, active_run_id)
    ];
    observations = [
        f"{item.id}: {item.tool}({item.service_id}) observed {item.observation}"
        for item in current_evidence
    ];

    if not current_evidence {
        return InvestigationResult(
            status="failed",
            tool_timeline=actual_timeline,
            explanation="No diagnostic evidence from the active simulation run was available.",
        );
    }

    return InvestigationResult(
        status="completed"
            if model_result.status == "completed"
            else model_result.status,
        tool_timeline=actual_timeline,
        observed_evidence=observations,
        candidate_root_causes=model_result.candidate_root_causes,
        discovered_dependencies=accepted_dependencies,
        explanation=model_result.explanation,
    );
}

def investigation_result_to_dict(result: InvestigationResult) -> dict[str, any] {
    return {
        "tool_timeline": result.tool_timeline,
        "observed_evidence": result.observed_evidence,
        "candidate_root_causes": result.candidate_root_causes,
        "discovered_dependencies": [
            {
                "source_id": item.source_id,
                "target_id": item.target_id,
                "kind": item.kind,
                "evidence_ids": item.evidence_ids,

            } for item in result.discovered_dependencies
        ],
        "explanation": result.explanation,

    };
}
