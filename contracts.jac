"""Stable JSON-compatible contracts shared by every SYMPHONY workstream."""

obj PackageInventoryItem {
    has name: str,
        ecosystem: str,
        version: str;
}

obj Service {
    has id: str,
        name: str,
        state: str = "healthy",
        inventory: list[PackageInventoryItem] = [];
}

obj Dependency {
    # source_id depends on target_id.
    has source_id: str,
        target_id: str,
        kind: str = "documented",
        evidence_ids: list[str] = [];
}

obj DashboardSummary {
    has total_services: int = 0,
        healthy_services: int = 0,
        degraded_services: int = 0,
        failed_services: int = 0,
        discovered_dependencies: int = 0,
        vulnerability_findings: int = 0;
}

obj DashboardState {
    has services: list[Service] = [],
        dependencies: list[Dependency] = [],
        summary: DashboardSummary = DashboardSummary(),
        simulation_run_id: str = "initial",
        service_mode: str = "mock",
        topology_source: str = "catalog",
        topology_error: str = "";
}

obj OperationError {
    has code: str,
        message: str;
}

obj OperationEnvelope {
    has status: str,
        data: dict[str, any] = {},
        error: OperationError | None = None;
}

obj Evidence {
    has id: str,
        tool: str,
        service_id: str,
        observation: dict[str, any],
        simulation_run_id: str;
}

obj InvestigationResult {
    has status: str,
        tool_timeline: list[str] = [],
        observed_evidence: list[str] = [],
        candidate_root_causes: list[str] = [],
        discovered_dependencies: list[Dependency] = [],
        explanation: str = "";
}

obj AssessedFinding {
    # One advisory the Security Analyst assessed; it must cite an advisory from the current scan.
    has advisory_id: str,
        package: str,
        risk: str,
        cited_advisory_ids: list[str] = [];
}

obj SecurityAssessment {
    has service_id: str,
        simulation_run_id: str,
        findings: list[AssessedFinding] = [],
        dependents: list[str] = [],
        priority: str = "low",
        rule_based_priority: str = "low",
        explanation: str = "";
}

obj RepairPreview {
    has before: list[dict[str, any]] = [],
        after: list[dict[str, any]] = [],
        outcome: str = "no_incident";
}

obj RecoveryProposal {
    has simulation_run_id: str,
        target_service_id: str,
        action: str,
        rationale: str = "",
        cited_evidence_ids: list[str] = [],
        preview: RepairPreview = RepairPreview();
}

sem SecurityAssessment.priority = "Priority low, medium, or high. Base it on cited advisories and dependents only.";
sem SecurityAssessment.explanation = "Concise, cautious explanation. Dependents are potentially exposed, never called vulnerable or compromised without direct evidence.";
sem AssessedFinding.cited_advisory_ids = "Advisory IDs from the current scan that support this risk statement.";
sem RecoveryProposal.action = "One action returned by list_repair_options.";
sem RecoveryProposal.cited_evidence_ids = "Evidence IDs from the current investigation that support the chosen target.";

sem InvestigationResult.status = "Investigation execution status, not service health. Use completed when diagnostic tools returned evidence, even when services are down or the cause remains uncertain. Provider failures are handled separately.";
sem InvestigationResult.tool_timeline = "Ordered descriptions of diagnostic tool calls actually used during this investigation.";
sem InvestigationResult.observed_evidence = "Concrete observations returned by diagnostic tools, without invented facts.";
sem InvestigationResult.candidate_root_causes = "Plausible root causes ranked from strongest to weakest support.";
sem InvestigationResult.discovered_dependencies = "Previously undocumented dependency relationships supported by trace evidence. Leave empty without such evidence.";
sem InvestigationResult.explanation = "A concise root-cause explanation that cites the observed evidence and clearly states uncertainty.";
