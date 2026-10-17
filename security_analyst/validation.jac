"""Validate a Security Analyst judgment against the scan it was given."""

import from contracts { AssessedFinding, OperationError, SecurityAssessment }
import from agent_support.claims { asserts_terms }
import from .tools { SecurityJudgment, advisories_in }

glob PRIORITY_RANK: dict[str, int] = {"low": 0, "medium": 1, "high": 2};
glob OVERSTATED_WORDS = ["compromised", "breached", "exploited", "hacked"];

def normalize_priority(priority: str) -> str {
    value = priority.strip().lower();
    # The application has three priority levels. Critical severity belongs
    # in its highest priority bucket, while unknown labels still fail validation.
    return "high" if value == "critical" else value;
}

def _error(code: str, message: str) -> OperationError {
    return OperationError(code=code, message=message);
}

def overstates_impact(text: str) -> bool {
    return asserts_terms(text, OVERSTATED_WORDS);
}

def validate_judgment(
    judgment: SecurityJudgment, scan: dict[str, any]
) -> OperationError | None {
    advisories = advisories_in(scan);
    known = {(item["advisory_id"], item["package"]) for item in advisories};
    known_ids = {item["advisory_id"] for item in advisories};
    if normalize_priority(judgment.priority) not in PRIORITY_RANK {
        return _error(
            "invalid_priority",
            f"Priority '{judgment.priority}' is not low, medium, or high."
        );
    }
    if not judgment.explanation.strip() {
        return _error("missing_explanation", "The assessment has no explanation.");
    }
    if overstates_impact(judgment.explanation) {
        return _error(
            "overstated_impact",
            "The explanation claims compromise without direct evidence."
        );
    }
    for finding in judgment.findings {
        if finding.advisory_id not in known_ids {
            return _error(
                "unsupported_advisory",
                f"Advisory '{finding.advisory_id}' is not in the current scan."
            );
        }
        if (finding.advisory_id, finding.package) not in known {
            return _error(
                "package_mismatch",
                f"Advisory '{finding.advisory_id}' does not belong to package '{finding.package}'."
            );
        }
        if len(finding.cited_advisory_ids) == 0 {
            return _error(
                "missing_citation",
                f"Finding '{finding.advisory_id}' cites no advisory."
            );
        }
        for cited in finding.cited_advisory_ids {
            if cited not in known_ids {
                return _error(
                    "unsupported_advisory",
                    f"Cited advisory '{cited}' is not in the current scan."
                );
            }
        }
        if not finding.risk.strip() {
            return _error(
                "missing_risk",
                f"Finding '{finding.advisory_id}' has no risk statement."
            );
        }
        if overstates_impact(finding.risk) {
            return _error(
                "overstated_impact",
                f"Finding '{finding.advisory_id}' claims compromise without direct evidence."
            );
        }
    }
    return None;
}

def complete_findings(
    judgment: SecurityJudgment, scan: dict[str, any]
) -> list[AssessedFinding] {
    # Every scanned advisory is reported. Ones the model skipped get a plain,
    # data-only statement instead of being silently dropped.
    assessed = {(item.advisory_id, item.package): item for item in judgment.findings};
    complete: list[AssessedFinding] = [];
    for advisory in advisories_in(scan) {
        advisory_id = advisory["advisory_id"];
        key = (advisory_id, advisory["package"]);
        if key in assessed {
            complete.append(assessed[key]);
        } else {
            complete.append(
                AssessedFinding(
                    advisory_id=advisory_id,
                    package=advisory["package"],
                    risk=f"Not assessed by the model. OSV reports: {advisory[
                        'summary'
                    ]} (severity: {advisory['severity']}).",
                    cited_advisory_ids=[advisory_id],
                )
            );
        }
    }
    return complete;
}

def build_assessment(
    judgment: SecurityJudgment,
    scan: dict[str, any],
    service_id: str,
    run_id: str,
    dependents: list[str],
    rule_based_priority: str,
) -> SecurityAssessment {
    priority = normalize_priority(judgment.priority);
    explanation = judgment.explanation;
    if judgment.priority.strip().lower() == "critical" {
        explanation = f"{explanation} Model priority '{judgment.priority.strip()}' maps to high on the application's low/medium/high priority scale.";
    }
    if PRIORITY_RANK[priority] < PRIORITY_RANK.get(rule_based_priority, 0) {
        explanation = f"{explanation} Note: the model priority ({priority}) is lower than the rule-based priority ({rule_based_priority}).";
    }
    return SecurityAssessment(
        service_id=service_id,
        simulation_run_id=run_id,
        findings=complete_findings(judgment, scan),
        dependents=dependents,
        priority=priority,
        rule_based_priority=rule_based_priority,
        explanation=explanation,
    );
}

def deterministic_assessment(
    scan: dict[str, any],
    service_id: str,
    run_id: str,
    dependents: list[str],
    rule_based_priority: str,
    explanation: str,
) -> SecurityAssessment {
    # Used when there is nothing for a model to judge. Never an "all clear" for a partial scan.
    return SecurityAssessment(
        service_id=service_id,
        simulation_run_id=run_id,
        findings=[],
        dependents=dependents,
        priority=rule_based_priority,
        rule_based_priority=rule_based_priority,
        explanation=explanation,
    );
}

def assessment_to_dict(
    assessment: SecurityAssessment,
    scan_status: str,
    finding_count: int,
    tool_timeline: list[str],
) -> dict[str, any] {
    return {
        "service_id": assessment.service_id,
        "simulation_run_id": assessment.simulation_run_id,
        "findings": [
            {
                "advisory_id": item.advisory_id,
                "package": item.package,
                "risk": item.risk,
                "cited_advisory_ids": item.cited_advisory_ids,

            } for item in assessment.findings
        ],
        "dependents": assessment.dependents,
        "priority": assessment.priority,
        "rule_based_priority": assessment.rule_based_priority,
        "explanation": assessment.explanation,
        "analysis_source": "deterministic" if finding_count == 0 else "model",
        "scan_status": scan_status,
        "finding_count": finding_count,
        "tool_timeline": tool_timeline,

    };
}
