"""Client model regressions; run with jac test dashboard/models/view_models.cl.jac.

Jac 0.34.19 requires this matching annex basename. A standalone suite under
tests/ cannot resolve the imported client model in Bun's temporary harness.
"""
# Literal wire payloads exercise decoding without server constructors or RPC.
def:pub envelope_fixture(status: str, data: dict[str, any] = {}) -> OperationEnvelope {
    return {"status": status, "data": data, "error": None} as OperationEnvelope;
}

def:pub scan_result(case_name: str) -> OperationEnvelope {
    if case_name == "failed" {
        return envelope_fixture(status="failed");
    }
    advisories: list[dict[str, any]] = [];
    if case_name != "empty" {
        advisories = [
            {
                "id": "FIXTURE-1",
                "summary": "Fixture advisory",
                "severity": None,
                "reference_url": "https://osv.dev/vulnerability/FIXTURE-1"
            }
        ];
    }
    return envelope_fixture(
        status="partial" if case_name == "partial" else "completed",
        data={
            "service_id": "payment",
            "packages": [
                {
                    "name": "fixture-package",
                    "version": "1.0.0",
                    "ecosystem": "PyPI",
                    "status": "partial" if case_name == "partial" else "completed",
                    "error": {"message": "Fixture lookup incomplete"}
                        if case_name == "partial"
                        else None,
                    "advisories": advisories
                }
            ]
        }
    );
}

test "scanner separates findings empty partial and failed cases" {
    for case_name in ["completed", "empty", "partial", "failed"] {
        result = scan_view(scan_result(case_name), "payment");
        assert result.feedback.status == (
            "completed" if case_name == "empty" else case_name
        );
        if case_name == "completed" {
            assert result.finding_count == 1;
            assert result.packages[0].advisories[0].severity == "unknown";
        } elif case_name == "empty" {
            assert result.packages[0].status == "completed"
            and result.finding_count == 0;
        } elif case_name == "partial" {
            assert result.packages[0].error and result.finding_count == 1;
        } else {
            assert len(result.packages) == 0;
        }
    }
}

test "malformed scans and unsafe links never become clean successful data" {
    result = scan_view(
        envelope_fixture(status="completed", data={"packages": []}), "payment"
    );
    assert result.feedback.status == "failed";
    assert safe_advisory_url("javascript:alert(1)") == "";
    assert safe_advisory_url("https://osv.dev/vulnerability/FIXTURE") != "";
    assert status_view(envelope_fixture(status="unexpected")).status == "failed";
}

test "investigation preserves timeline evidence candidates and discoveries" {
    result = investigation_view(
        envelope_fixture(
            status="completed",
            data={
                "tool_timeline": [
                    "check_service_health(payment)",
                    "trace_requests(payment)"
                ],
                "candidate_root_causes": ["Auth unavailable"],
                "explanation": "Supported fixture explanation",
                "evidence": [
                    {
                        "id": "trace-1",
                        "tool": "trace_requests",
                        "service_id": "payment",
                        "simulation_run_id": "run-1",
                        "observation": {
                            "source_id": "payment",
                            "target_id": "auth",
                            "message": "timeout"
                        }
                    }
                ],
                "discovered_dependencies": [
                    {
                        "source_id": "payment",
                        "target_id": "auth",
                        "evidence_ids": ["trace-1"]
                    }
                ]
            }
        )
    );
    assert len(result.timeline) == 2 and len(result.dependencies) == 1;
    assert result.dependencies[0].kind == "discovered";
    assert "timeout" in result.evidence[0].observation;
    assert result.candidates[0] == "Auth unavailable" and result.explanation;
}

test "request guard discards old runs services requests and epochs" {
    assert request_is_current(
        1, 1, 2, 2, "payment", "payment", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 2, 2, 2, "payment", "payment", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 1, 1, 2, "payment", "payment", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 1, 2, 2, "payment", "catalog", "run-1", "run-1", "run-1"
    );
    assert not request_is_current(
        1, 1, 2, 2, "payment", "payment", "run-1", "run-2", "run-1"
    );
    assert not request_is_current(
        1, 1, 2, 2, "payment", "payment", "run-1", "run-1", "run-0"
    );
}

test "discovered edges deduplicate and require evidence references" {
    documented = [
        DependencyView(source_id="payment", target_id="database", kind="documented")
    ];
    proposed = [
        DependencyView(source_id="payment", target_id="auth", evidence_ids=["trace-1"])
    ];
    assert len(merge_dependencies(documented, proposed + proposed)) == 2;
    assert len(
        merge_dependencies(
            documented, [DependencyView(source_id="payment", target_id="auth")]
        )
    ) == 1;
}

test "recovery comparison preserves missing after states as unknown" {
    view = recovery_view(
        envelope_fixture(
            status="completed",
            data={
                "candidate_repair": "Restore Auth",
                "before": [
                    {"id": "auth", "state": "down"},
                    {"id": "payment", "state": "down"}
                ],
                "after": [{"id": "auth", "state": "healthy"}],
                "outcome": "Partial recovery"
            }
        )
    );
    assert len(view.rows) == 2;
    assert view.rows[0].after == "healthy" and view.rows[1].after == "unknown";
    assert view.outcome == "Partial recovery";
}

test "impact exposure accepts a sentence list or a single string" {
    listed = impact_view(
        envelope_fixture(
            status="completed",
            data={
                "dependent_services": ["payment"],
                "relationships": [],
                "potential_exposure": ["First sentence.", "Second sentence."],
                "priority": "medium"
            }
        )
    );
    single = impact_view(
        envelope_fixture(
            status="completed",
            data={
                "dependent_services": [],
                "relationships": [],
                "potential_exposure": "One sentence.",
                "priority": "low"
            }
        )
    );
    assert listed.exposure == "First sentence. Second sentence.";
    assert single.exposure == "One sentence.";
}

test "evidence formatting retains concrete nested JSON observations" {
    description = observation_text(
        {"source_id": "payment", "target_id": "auth", "details": {"message": "timeout"}}
    );
    assert "payment" in description
    and "auth" in description
    and "timeout" in description;
}

test "overview counts derive from visible states and accepted relationships" {
    state = {
        "services": [
            {"id": "auth", "name": "Auth", "state": "down"},
            {"id": "payment", "name": "Payment", "state": "degraded"}
        ]
    } as DashboardState;
    summary = overview_summary(
        state,
        [
            DependencyView(
                source_id="payment", target_id="auth", evidence_ids=["trace-1"]
            )
        ],
        {"payment": 2}
    );
    assert summary.total_services == 2
    and summary.failed_services == 1
    and summary.degraded_services == 1;
    assert summary.discovered_dependencies == 1 and summary.vulnerability_findings == 2;
}

test "invalid RPC snapshots cannot replace the displayed dashboard" {
    assert not dashboard_is_valid({});
    assert not dashboard_is_valid(
        {"services": [], "dependencies": None, "simulation_run_id": "run-1"}
    );
    assert dashboard_is_valid(
        {"services": [], "dependencies": [], "simulation_run_id": "run-1"}
    );
}

test "automation helpers detect only newly unhealthy services and decode steps" {
    previous = {"frontend": "healthy", "payment": "down"};
    current = {"frontend": "down", "payment": "down"};
    assert newly_unhealthy(previous, current) == ["frontend"];
    decoded = operation_envelope(
        {
            "status": "failed",
            "data": {},
            "error": {"code": "fixture", "message": "Fixture failure"}
        }
    );
    assert decoded.status == "failed";
    assert decoded.error is not None and decoded.error.code == "fixture";
}


test "agent assessment keeps model and rule priorities separate with incomplete coverage" {
    view = security_assessment_view(
        envelope_fixture(
            status="partial",
            data={
                "priority": "low",
                "rule_based_priority": "high",
                "priority_below_rule_based": True,
                "scan_status": "partial",
                "explanation": "Review incomplete coverage",
                "findings": [
                    {
                        "advisory_id": "ADV-1",
                        "package": "example",
                        "risk": "Review the advisory",
                        "cited_advisory_ids": ["ADV-1"]
                    }
                ]
            }
        )
    );
    assert view.feedback.status == "partial" and view.priority_lower;
    assert view.priority == "low" and view.rule_priority == "high";
    assert view.scan_status == "partial" and view.findings[0].citations == ["ADV-1"];
    assert security_assessment_view(envelope_fixture(status="failed")).findings == [];
}

test "recovery proposal shows citations and actual failed verification" {
    view = recovery_proposal_view(
        envelope_fixture(
            status="completed",
            data={
                "target_service_id": "catalog",
                "action": "rollback",
                "rationale": "Try the cited hypothesis",
                "cited_evidence_ids": ["trace-1"],
                "preview": {
                    "before": [{"id": "payment", "state": "down"}],
                    "after": [{"id": "payment", "state": "down"}],
                    "outcome": "not_recovered"
                }
            }
        )
    );
    assert view.target == "catalog" and view.action == "rollback";
    assert view.preview.outcome == "not_recovered";
    assert view.preview.rows[0].after == "down" and view.citations == ["trace-1"];
    assert recovery_proposal_view(envelope_fixture(status="failed")).preview.rows == [];
}

test "new agent requests have independent guard counters" {
    scope = RequestScope();
    scope.request_ids["security_analysis"] += 1;
    assert scope.request_ids["recovery_agent"] == 0;
    assert scope.request_ids["scan"] == 0;
    assert not request_is_current(
        1,
        1,
        0,
        scope.request_ids["security_analysis"],
        "payment",
        "payment",
        "r",
        "r",
        "r"
    );
}

test "zero-advisory assessments retain their deterministic source label" {
    view = security_assessment_view(
        envelope_fixture(
            status="completed",
            data={
                "analysis_source": "deterministic",
                "findings": [],
                "priority": "high",
                "rule_based_priority": "high"
            }
        )
    );
    assert view.source == "deterministic" and view.findings == [];
    assert security_assessment_view(envelope_fixture(status="completed")).source == "model";
}
