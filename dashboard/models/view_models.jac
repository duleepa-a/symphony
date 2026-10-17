"""Presentation models and defensive decoding at the JSON integration boundary."""

import from contracts {
    OperationEnvelope,
    DashboardState,
    Dependency,
    DashboardSummary
}

obj PanelStatus {
    has status: str = "idle",
        message: str = "";
}

obj AdvisoryView {
    has id: str,
        summary: str = "",
        severity: str = "unknown",
        url: str = "";
}

obj PackageView {
    has name: str,
        ecosystem: str = "",
        version: str = "",
        status: str = "failed",
        error: str = "",
        advisories: list[AdvisoryView] = [];
}

obj ScanView {
    has feedback: PanelStatus = PanelStatus(),
        service_id: str = "",
        packages: list[PackageView] = [],
        finding_count: int = 0;
}

obj EvidenceView {
    has id: str,
        tool: str = "",
        service_id: str = "",
        observation: str = "",
        simulation_run_id: str = "";
}

obj InvestigationView {
    has feedback: PanelStatus = PanelStatus(),
        timeline: list[str] = [],
        evidence: list[EvidenceView] = [],
        candidates: list[str] = [],
        dependencies: list[Dependency] = [],
        explanation: str = "";
}

obj ImpactView {
    has feedback: PanelStatus = PanelStatus(),
        dependents: list[str] = [],
        relationships: list[str] = [],
        exposure: str = "",
        priority: str = "unknown";
}

obj RecoveryRow {
    has service_id: str,
        before: str = "unknown",
        after: str = "unknown";
}

obj RecoveryView {
    has feedback: PanelStatus = PanelStatus(),
        repair: str = "",
        rows: list[RecoveryRow] = [],
        outcome: str = "";
}

def value(raw: any, key: str, fallback: any = None) -> any {
    if raw is None {
        return fallback;
    }
    return raw[key] if key in raw else fallback;
}

def text(raw: any, fallback: str = "") -> str {
    return fallback if raw is None else str(raw);
}

def observation_text(raw: any) -> str {
    # Jac 0.37.25 client isinstance(dict) does not recognize plain JSON objects.
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

def strings(raw: any) -> list[str] {
    if raw is None {
        return [];
    }
    return [str(item) for item in raw];
}

def status_view(result: OperationEnvelope) -> PanelStatus {
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

def is_busy(status: str) -> bool {
    return status in ["loading", "running"];
}

def has_result(status: str) -> bool {
    return status in ["completed", "partial"];
}

def safe_advisory_url(url: str) -> str {
    return url if url.startswith("https://") or url.startswith("http://") else "";
}

def scan_view(result: OperationEnvelope, service_id: str) -> ScanView {
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

def investigation_view(result: OperationEnvelope) -> InvestigationView {
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
            Dependency(
                source_id=text(value(raw, "source_id", "")),
                target_id=text(value(raw, "target_id", "")),
                kind="discovered",
                evidence_ids=strings(value(raw, "evidence_ids", []))
            )
        );
    }
    return view;
}

def impact_view(result: OperationEnvelope) -> ImpactView {
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
    view.exposure = text(
        value(
            result.data,
            "potential_exposure",
            "Potential exposure only; compromise has not been established."
        )
    );
    view.priority = text(value(result.data, "priority", "unknown"));
    return view;
}

def recovery_view(result: OperationEnvelope) -> RecoveryView {
    view = RecoveryView(feedback=status_view(result));
    if not has_result(view.feedback.status) {
        return view;
    }
    view.repair = text(value(result.data, "candidate_repair", ""));
    view.outcome = text(
        value(result.data, "outcome", "Verification outcome unavailable.")
    );
    before = value(result.data, "before", []);
    after = value(result.data, "after", []);
    for item in before {
        service_id = text(value(item, "id", value(item, "service_id", "")));
        after_state = "unknown";
        for updated in after {
            if text(value(updated, "id", value(updated, "service_id", "")))
                == service_id {
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

def request_is_current(
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

def merge_dependencies(
    documented: list[Dependency], discovered: list[Dependency]
) -> list[Dependency] {
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

def overview_summary(
    state: DashboardState, dependencies: list[Dependency], findings: dict[str, int]
) -> DashboardSummary {
    return DashboardSummary(
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
