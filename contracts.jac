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
        simulation_run_id: str = "initial";
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

sem InvestigationResult.status = "Investigation completion status. Use completed only when the conclusion is supported by diagnostic evidence.";
sem InvestigationResult.tool_timeline = "Ordered descriptions of diagnostic tool calls actually used during this investigation.";
sem InvestigationResult.observed_evidence = "Concrete observations returned by diagnostic tools, without invented facts.";
sem InvestigationResult.candidate_root_causes = "Plausible root causes ranked from strongest to weakest support.";
sem InvestigationResult.discovered_dependencies = "Previously undocumented dependency relationships supported by trace evidence. Leave empty without such evidence.";
sem InvestigationResult.explanation = "A concise root-cause explanation that cites the observed evidence and clearly states uncertainty.";
