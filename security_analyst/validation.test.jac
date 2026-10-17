"""Security Analyst judgment validation against the scan it was given."""

import from contracts { AssessedFinding }
import from .fixtures { fixture_scan }
import from .tools { SecurityJudgment }

def scan_data -> dict[str, any] {
    return fixture_scan("findings").data;
}

def finding(
    advisory_id: str = "GHSA-fixture-0001",
    package: str = "pyjwt",
    risk: str = "Unconfirmed risk to token validation.",
    cited: list[str] = ["GHSA-fixture-0001"],
) -> AssessedFinding {
    return AssessedFinding(
        advisory_id=advisory_id, package=package, risk=risk, cited_advisory_ids=cited
    );
}

def judgment_with(
    findings: list[AssessedFinding],
    priority: str = "medium",
    explanation: str = "One advisory affects the scanned service.",
) -> SecurityJudgment {
    return SecurityJudgment(
        findings=findings, priority=priority, explanation=explanation
    );
}

def problem_code(judgment: SecurityJudgment) -> str {
    problem = validate_judgment(judgment, scan_data());
    return problem.code if problem is not None else "";
}

test "a cited finding from the scan is accepted" {
    assert problem_code(judgment_with([finding()])) == "";
}

test "invented advisories and mismatched packages are rejected" {
    assert problem_code(judgment_with([finding(advisory_id="GHSA-invented")])) == "unsupported_advisory";
    assert problem_code(judgment_with([finding(cited=["GHSA-invented"])])) == "unsupported_advisory";
    assert problem_code(judgment_with([finding(package="lodash")])) == "package_mismatch";
    assert problem_code(judgment_with([finding(cited=[])])) == "missing_citation";
}

test "priority and text must be present and valid" {
    assert problem_code(judgment_with([finding()], priority="critical")) == "invalid_priority";
    assert problem_code(judgment_with([finding()], explanation=" ")) == "missing_explanation";
    assert problem_code(judgment_with([finding(risk=" ")])) == "missing_risk";
}

test "affirmative compromise claims are rejected but negated ones are allowed" {
    assert overstates_impact("Payment was compromised by this issue.");
    assert overstates_impact("Dependents are breached.");
    assert not overstates_impact("There is no direct evidence Payment is compromised.");
    assert not overstates_impact("Dependents may be operationally affected.");
    assert problem_code(
        judgment_with([finding()], explanation="Payment is compromised.")
    ) == "overstated_impact";
    assert problem_code(
        judgment_with([finding(risk="Auth was exploited in the wild.")])
    ) == "overstated_impact";
}

test "skipped advisories are still reported and a lower priority is flagged" {
    judgment = judgment_with([], priority="low");
    assessment = build_assessment(
        judgment, scan_data(), "auth", "run-1", ["payment"], "high"
    );
    assert len(assessment.findings) == 1;
    assert assessment.findings[0].advisory_id == "GHSA-fixture-0001";
    assert "Not assessed by the model" in assessment.findings[0].risk;
    assert assessment.priority == "low" and assessment.rule_based_priority == "high";
    assert "lower than the rule-based priority" in assessment.explanation;
}
