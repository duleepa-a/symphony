"""Presentation models and defensive decoding at the JSON integration boundary."""

import type from ...contracts { OperationEnvelope, DashboardState, Dependency }

obj:pub RequestScope {
    has changing: bool = False,
        generation: int = 0,
        load_request: int = 0,
        selected_service: str = "payment",
        run_id: str = "",
        request_ids: dict[str, int] = {
            "investigation": 0,
            "scan": 0,
            "impact": 0,
            "recovery": 0,
            "security_analysis": 0,
            "recovery_agent": 0
        };
}

obj:pub DependencyView {
    has source_id: str,
        target_id: str,
        kind: str = "discovered",
        evidence_ids: list[str] = [];
}

obj:pub OverviewView {
    has total_services: int = 0,
        healthy_services: int = 0,
        degraded_services: int = 0,
        failed_services: int = 0,
        discovered_dependencies: int = 0,
        vulnerability_findings: int = 0;
}

obj:pub PanelStatus {
    has status: str = "idle",
        message: str = "";
}

obj:pub AdvisoryView {
    has id: str,
        summary: str = "",
        severity: str = "unknown",
        url: str = "";
}

obj:pub PackageView {
    has name: str,
        ecosystem: str = "",
        version: str = "",
        status: str = "failed",
        error: str = "",
        advisories: list[AdvisoryView] = [];
}

obj:pub ScanView {
    has feedback: PanelStatus = PanelStatus(),
        service_id: str = "",
        packages: list[PackageView] = [],
        finding_count: int = 0;
}

obj:pub EvidenceView {
    has id: str,
        tool: str = "",
        service_id: str = "",
        observation: str = "",
        simulation_run_id: str = "";
}

obj:pub InvestigationView {
    has feedback: PanelStatus = PanelStatus(),
        timeline: list[str] = [],
        evidence: list[EvidenceView] = [],
        candidates: list[str] = [],
        dependencies: list[DependencyView] = [],
        explanation: str = "";
}

obj:pub ImpactView {
    has feedback: PanelStatus = PanelStatus(),
        dependents: list[str] = [],
        relationships: list[str] = [],
        exposure: str = "",
        priority: str = "unknown",
        source: str = "simulation";
}

obj:pub RecoveryRow {
    has service_id: str,
        before: str = "unknown",
        after: str = "unknown";
}

obj:pub RecoveryView {
    has feedback: PanelStatus = PanelStatus(),
        repair: str = "",
        rows: list[RecoveryRow] = [],
        outcome: str = "",
        source: str = "simulation",
        verification_note: str = "";
}

def:pub value(raw: dict[str, any] | None, key: str, fallback: any = None) -> any {
    if raw is None {
        return fallback;
    }
    return raw[key] if key in raw else fallback;
}

def:pub operation_envelope(raw: dict[str, any]) -> OperationEnvelope {
    problem = value(raw, "error", None);
    return {
        "status": text(value(raw, "status", "failed")),
        "data": value(raw, "data", {}),
        "error": {
            "code": text(value(problem, "code", "assessment_step_failed")),
            "message": text(value(problem, "message", "Assessment step failed."))
        }
            if problem
            else None
    } as OperationEnvelope;
}

def:pub service_states(snapshot: DashboardState) -> dict[str, str] {
    return {service.id: service.state for service in snapshot.services};
}

def:pub newly_unhealthy(
    previous: dict[str, str], current: dict[str, str]
) -> list[str] {
    return [
        service_id
        for (service_id, state) in current.items()
        if state in ["down", "degraded"]
        and previous.get(service_id, "healthy") not in ["down", "degraded"]
    ];
}

def:pub dashboard_is_valid(raw: any) -> bool {
    return bool(raw)
    and isinstance(value(raw, "services"), list)
    and isinstance(value(raw, "dependencies"), list)
    and isinstance(value(raw, "simulation_run_id"), str)
    and bool(value(raw, "simulation_run_id"));
}

def:pub text(raw: any, fallback: str = "") -> str {
    return fallback if raw is None else str(raw);
}

def:pub observation_text(raw: any) -> str {
    # Decode JSON objects recursively without relying on client dict identity.
    if raw is None or isinstance(raw, (str, int, float, bool)) {
        return text(raw);
    }
    if isinstance(raw, list) {
        return ", ".join([observation_text(item) for item in raw]);
    }
    return "; ".join(
        [f"{key}: {observation_text(item)}" for (key, item) in raw.items()]
    );
}

def:pub strings(raw: any) -> list[str] {
    if raw is None {
        return [];
    }
    return [str(item) for item in raw];
}

def:pub status_view(result: OperationEnvelope) -> PanelStatus {
    allowed = [
        "idle",
        "loading",
        "running",
        "completed",
        "partial",
        "failed",
        "not_implemented",
        "simulation_not_connected"
    ];
    if result.status not in allowed {
        return PanelStatus(
            status="failed", message="The operation returned an unsupported status."
        );
    }
    return PanelStatus(
        status=result.status, message=result.error.message if result.error else ""
    );
}

def:pub is_busy(status: str) -> bool {
    return status in ["loading", "running"];
}

def:pub has_result(status: str) -> bool {
    return status in ["completed", "partial"];
}

def:pub safe_advisory_url(url: str) -> str {
    return url if url.startswith("https://") or url.startswith("http://") else "";
}

def:pub scan_view(result: OperationEnvelope, service_id: str) -> ScanView {
    view = ScanView(feedback=status_view(result), service_id=service_id);
    if not has_result(view.feedback.status) {
        return view;
    }
    for raw in value(result.data, "packages", []) {
        package_result = PackageView(
            name=text(value(raw, "name", value(raw, "package", "Unknown package"))),
            ecosystem=text(value(raw, "ecosystem", "")),
            version=text(value(raw, "version", "")),
            status=text(value(raw, "status", "failed"))
        );
        problem = value(raw, "error", None);
        if problem is not None {
            package_result.error = text(
                value(problem, "message", "Package lookup failed.")
            );
        }
        for advisory in value(raw, "advisories", []) {
            package_result.advisories.append(
                AdvisoryView(
                    id=text(value(advisory, "id", "Unknown advisory")),
                    summary=text(value(advisory, "summary", "No summary supplied.")),
                    severity=text(value(advisory, "severity", "unknown")) or "unknown",
                    url=safe_advisory_url(
                        text(
                            value(advisory, "reference_url", value(advisory, "url", ""))
                        )
                    )
                )
            );
        }
        view.packages.append(package_result);
        view.finding_count += len(package_result.advisories);
    }
    if not view.packages and view.feedback.status == "completed" {
        view.feedback = PanelStatus(
            status="failed",
            message="The scanner returned no package results; this is not a verified clean scan."
        );
    }
    return view;
}

def:pub investigation_view(result: OperationEnvelope) -> InvestigationView {
    view = InvestigationView(feedback=status_view(result));
    if not has_result(view.feedback.status) {
        return view;
    }
    view.timeline = strings(
        value(result.data, "tool_timeline", value(result.data, "timeline", []))
    );
    view.candidates = strings(
        value(
            result.data, "candidate_root_causes", value(result.data, "candidates", [])
        )
    );
    view.explanation = text(value(result.data, "explanation", ""));
    for raw in value(
        result.data, "evidence", value(result.data, "observed_evidence", [])
    ) {
        if isinstance(raw, str) {
            view.evidence.append(EvidenceView(id="", observation=raw));
        } else {
            view.evidence.append(
                EvidenceView(
                    id=text(value(raw, "id", "")),
                    tool=text(value(raw, "tool", "")),
                    service_id=text(value(raw, "service_id", "")),
                    observation=observation_text(value(raw, "observation", "")),
                    simulation_run_id=text(value(raw, "simulation_run_id", ""))
                )
            );
        }
    }
    for raw in value(result.data, "discovered_dependencies", []) {
        view.dependencies.append(
            DependencyView(
                source_id=text(value(raw, "source_id", "")),
                target_id=text(value(raw, "target_id", "")),
                kind="discovered",
                evidence_ids=strings(value(raw, "evidence_ids", []))
            )
        );
    }
    return view;
}

def:pub impact_view(result: OperationEnvelope) -> ImpactView {
    view = ImpactView(feedback=status_view(result));
    if not has_result(view.feedback.status) {
        return view;
    }
    for raw in value(result.data, "dependent_services", []) {
        view.dependents.append(
            raw
                if isinstance(raw, str)
                else text(value(raw, "name", value(raw, "id", "Unknown service")))
        );
    }
    for raw in value(result.data, "relationships", []) {
        view.relationships.append(
            raw
                if isinstance(raw, str)
                else f"{text(value(raw, 'source_id', ''))} → {text(
                    value(raw, 'target_id', '')
                )} ({text(value(raw, 'kind', 'documented'))})"
        );
    }
    exposure = value(
        result.data,
        "potential_exposure",
        "Potential exposure only; compromise has not been established."
    );
    view.exposure = " ".join([text(item) for item in exposure])
        if isinstance(exposure, list)
        else text(exposure);
    view.priority = text(value(result.data, "priority", "unknown"));
    view.source = text(value(result.data, "analysis_source", "simulation"));
    return view;
}

def:pub recovery_view(result: OperationEnvelope) -> RecoveryView {
    view = RecoveryView(feedback=status_view(result));
    if not has_result(view.feedback.status) {
        return view;
    }
    view.repair = text(value(result.data, "candidate_repair", ""));
    view.outcome = text(
        value(result.data, "outcome", "Verification outcome unavailable.")
    );
    view.source = text(value(result.data, "analysis_source", "simulation"));
    view.verification_note = text(value(result.data, "verification_note", ""));
    before = value(result.data, "before", []);
    after = value(result.data, "after", []);
    for item in before {
        service_id = text(value(item, "id", value(item, "service_id", "")));
        after_state = "unknown";
        for updated in after {
            if text(
                value(updated, "id", value(updated, "service_id", ""))
            ) == service_id {
                after_state = text(value(updated, "state", "unknown"));
            }
        }
        view.rows.append(
            RecoveryRow(
                service_id=service_id,
                before=text(value(item, "state", "unknown")),
                after=after_state
            )
        );
    }
    return view;
}

def:pub request_is_current(
    request_epoch: int,
    active_epoch: int,
    request_id: int,
    active_id: int,
    requested_service: str,
    selected_service: str,
    requested_run: str,
    active_run: str,
    response_run: str
) -> bool {
    return request_epoch == active_epoch
    and request_id == active_id
    and requested_service == selected_service
    and requested_run == active_run
    and (not response_run or response_run == active_run);
}

def:pub merge_dependencies(
    documented: list[Dependency | DependencyView],
    discovered: list[Dependency | DependencyView]
) -> list[Dependency | DependencyView] {
    merged = documented.copy();
    for dependency in discovered {
        if dependency.kind != "discovered" or not dependency.evidence_ids {
            continue;
        }
        if not `any(
            item.source_id == dependency.source_id
            and item.target_id == dependency.target_id for item in merged
        ) {
            merged.append(dependency);
        }
    }
    return merged;
}

def:pub overview_summary(
    state: DashboardState,
    dependencies: list[Dependency | DependencyView],
    findings: dict[str, int]
) -> OverviewView {
    return OverviewView(
        total_services=len(state.services),
        healthy_services=len(
            [
                s
                for s in state.services
                if s.state == "healthy"
            ]
        ),
        degraded_services=len(
            [
                s
                for s in state.services
                if s.state == "degraded"
            ]
        ),
        failed_services=len(
            [
                s
                for s in state.services
                if s.state == "down"
            ]
        ),
        discovered_dependencies=len(
            [
                dependency
                for dependency in dependencies
                if dependency.kind == "discovered"
            ]
        ),
        vulnerability_findings=sum(findings.values())
    );
}


obj:pub AssessedFindingView {
    has advisory_id: str,
        package: str,
        risk: str,
        citations: list[str] = [];
}

obj:pub SecurityAssessmentView {
    has feedback: PanelStatus = PanelStatus(),
        findings: list[AssessedFindingView] = [],
        dependents: list[str] = [],
        priority: str = "unknown",
        rule_priority: str = "unknown",
        priority_lower: bool = False,
        explanation: str = "",
        scan_status: str = "unknown",
        source: str = "model";
}

obj:pub ServiceRiskView {
    has service_id: str,
        service_name: str,
        scan_status: str = "failed",
        assessment_status: str = "failed",
        finding_count: int = 0,
        high_finding_count: int = 0,
        priority: str = "unknown";
}

obj:pub RecoveryProposalView {
    has feedback: PanelStatus = PanelStatus(),
        target: str = "",
        action: str = "",
        rationale: str = "",
        citations: list[str] = [],
        preview: RecoveryView = RecoveryView();
}

def:pub security_assessment_view(result: OperationEnvelope) -> SecurityAssessmentView {
    view = SecurityAssessmentView(feedback=status_view(result));
    if not has_result(view.feedback.status) {
        return view;
    }
    data = result.data;
    view.priority = text(value(data, "priority", "unknown"));
    view.rule_priority = text(value(data, "rule_based_priority", "unknown"));
    view.priority_lower = bool(value(data, "priority_below_rule_based", False));
    view.explanation = text(value(data, "explanation", ""));
    view.dependents = strings(value(data, "dependents", []));
    view.scan_status = text(value(data, "scan_status", "unknown"));
    view.source = text(value(data, "analysis_source", "model"));
    for item in value(data, "findings", []) {
        view.findings.append(
            AssessedFindingView(
                advisory_id=text(value(item, "advisory_id", "")),
                package=text(value(item, "package", "")),
                risk=text(value(item, "risk", "")),
                citations=strings(value(item, "cited_advisory_ids", []))
            )
        );
    }
    return view;
}

def:pub recovery_proposal_view(result: OperationEnvelope) -> RecoveryProposalView {
    view = RecoveryProposalView(feedback=status_view(result));
    if not has_result(view.feedback.status) {
        return view;
    }
    data = result.data;
    view.target = text(value(data, "target_service_id", ""));
    view.action = text(value(data, "action", ""));
    view.rationale = text(value(data, "rationale", ""));
    view.citations = strings(value(data, "cited_evidence_ids", []));
    preview = value(data, "preview", {});
    view.preview = recovery_view(
        {
            "status": result.status,
            "data": {** preview, "candidate_repair": view.action},
            "error": None
        } as OperationEnvelope
    );
    return view;
}
