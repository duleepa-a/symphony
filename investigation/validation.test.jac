"""Evidence gate tests for Investigator output."""

import from .fixtures { stale_evidence_fixture }

def _supported_model_result(evidence_id: str) -> InvestigationResult {
    return InvestigationResult(
        status="completed",
        tool_timeline=["invented model timeline"],
        observed_evidence=["invented model evidence"],
        candidate_root_causes=["Auth is unavailable"],
        discovered_dependencies=[
            Dependency(
                source_id="payment",
                target_id="auth",
                kind="discovered",
                evidence_ids=[evidence_id],
            )
        ],
        explanation="Trace evidence supports Payment depending on Auth.",
    );
}

test "accepts dependency backed by current trace evidence" {
    evidence = Evidence(
        id="trace-current",
        tool="trace_requests",
        service_id="payment",
        observation={"source_id": "payment", "target_id": "auth"},
        simulation_run_id="run-current",
    );
    result = validate_investigation_result(
        _supported_model_result(evidence.id),
        ["trace_requests(payment)"],
        [evidence],
        "run-current",
    );
    assert result.status == "completed";
    assert len(result.discovered_dependencies) == 1;
    assert result.tool_timeline == ["trace_requests(payment)"];
    assert "trace-current" in result.observed_evidence[0];
}

test "rejects unsupported model dependency claim" {
    evidence = Evidence(
        id="trace-current",
        tool="trace_requests",
        service_id="payment",
        observation={"source_id": "payment", "target_id": "database"},
        simulation_run_id="run-current",
    );
    result = validate_investigation_result(
        _supported_model_result(evidence.id),
        ["trace_requests(payment)"],
        [evidence],
        "run-current",
    );
    assert result.status == "completed";
    assert len(result.discovered_dependencies) == 0;
}

test "non-trace evidence cannot support discovered edge" {
    evidence = Evidence(
        id="health-current",
        tool="check_service_health",
        service_id="payment",
        observation={"source_id": "payment", "target_id": "auth"},
        simulation_run_id="run-current",
    );
    result = validate_investigation_result(
        _supported_model_result(evidence.id),
        ["check_service_health(payment)"],
        [evidence],
        "run-current",
    );
    assert len(result.discovered_dependencies) == 0;
}

test "stale evidence is rejected" {
    result = validate_investigation_result(
        _supported_model_result("trace_requests-payment-stale"),
        ["trace_requests(payment)"],
        stale_evidence_fixture(),
        "run-current",
    );
    assert result.status == "failed";
    assert len(result.observed_evidence) == 0;
    assert len(result.discovered_dependencies) == 0;
    assert "active simulation run" in result.explanation;
}
