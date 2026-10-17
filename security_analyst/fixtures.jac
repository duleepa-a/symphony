"""Static scan inputs and analyst results for dashboard and integration work. Not production data."""

import from contracts { OperationEnvelope, OperationError }
import from agent_support.models { agent_failure }

glob FIXTURE_RUN = "fixture-run";

def _package(status: str, with_finding: bool, error: str = "") -> dict[str, any] {
    return {
        "package": "pyjwt",
        "ecosystem": "PyPI",
        "version": "1.7.1",
        "status": status,
        "findings": [
            {
                "advisory_id": "GHSA-fixture-0001",
                "summary": "Fixture advisory for token validation",
                "severity": "unknown",
                "reference_url": "https://example.invalid/GHSA-fixture-0001",
                "package": "pyjwt",
                "ecosystem": "PyPI",
                "version": "1.7.1",

            }
        ]
            if with_finding
            else [],
        "error": error,

    };
}

def fixture_scan(case_name: str) -> OperationEnvelope {
    data = {
        "service_id": "auth",
        "inventory": [{"name": "pyjwt", "ecosystem": "PyPI", "version": "1.7.1"}],
        "simulation_run_id": FIXTURE_RUN,

    };
    if case_name == "failed" {
        return OperationEnvelope(
            status="failed",
            data={
                ** data,
                "packages": [_package("failed", False, "OSV network error")],
                "finding_count": 0
            },
            error=OperationError(
                code="osv_scan_failed",
                message="Every package lookup failed; no zero-findings claim was made."
            ),
        );
    }
    if case_name == "partial" {
        return OperationEnvelope(
            status="partial",
            data={
                ** data,
                "packages": [_package("partial", True, "details unavailable")],
                "finding_count": 1
            },
            error=OperationError(
                code="osv_scan_partial",
                message="Some advisory data could not be retrieved or normalized."
            ),
        );
    }
    has_finding = case_name != "none";
    return OperationEnvelope(
        status="completed",
        data={
            ** data,
            "packages": [_package("completed", has_finding)],
            "finding_count": 1 if has_finding else 0,

        },
    );
}

def fixture_assessment_completed -> OperationEnvelope {
    return OperationEnvelope(
        status="completed",
        data={
            "service_id": "auth",
            "simulation_run_id": FIXTURE_RUN,
            "findings": [
                {
                    "advisory_id": "GHSA-fixture-0001",
                    "package": "pyjwt",
                    "risk": "Auth validates tokens with this package; severity is unknown, so treat the risk as unconfirmed.",
                    "cited_advisory_ids": ["GHSA-fixture-0001"],

                }
            ],
            "dependents": ["payment", "api_gateway", "frontend"],
            "priority": "medium",
            "rule_based_priority": "high",
            "explanation": "One advisory affects Auth. Dependents may be operationally affected; there is no direct evidence they are vulnerable. Note: the model priority (medium) is lower than the rule-based priority (high).",
            "scan_status": "completed",
            "finding_count": 1,
            "tool_timeline": ["get_scan_results()", "get_impact(auth)"],

        },
    );
}

def fixture_assessment_failed -> OperationEnvelope {
    return agent_failure(
        "security_analyst_authentication_error", "The model credential was rejected."
    );
}
