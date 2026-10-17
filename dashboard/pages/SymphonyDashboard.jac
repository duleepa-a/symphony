"""Page orchestrator: owns state, delegates rendering and boundary decoding."""
import from "@jac/runtime" { __jacClearCache }
import type from ...contracts { DashboardState, Dependency, OperationEnvelope }
sv import from ...operations {
    get_dashboard_state,
    start_incident,
    reset_incident,
    run_investigation,
    scan_service_dependencies,
    analyze_security_impact,
    preview_recovery,
    run_security_analysis,
    run_recovery_agent
}
import from ..models.view_models {
    dashboard_is_valid,
    RequestScope,
    DependencyView,
    PanelStatus,
    ScanView,
    InvestigationView,
    ImpactView,
    RecoveryView,
    SecurityAssessmentView,
    RecoveryProposalView,
    security_assessment_view,
    recovery_proposal_view,
    is_busy,
    has_result,
    status_view,
    scan_view,
    investigation_view,
    impact_view,
    recovery_view,
    request_is_current,
    merge_dependencies,
    overview_summary,
    value,
    text
}
import from ..atoms.ActionButton { ActionButton }
import from ..organisms.TopBar { TopBar }
import from ..organisms.SystemOverview { SystemOverview }
import from ..organisms.DependencyGraph { DependencyGraph }
import from ..organisms.IncidentPanel { IncidentPanel }
import from ..organisms.InvestigationPanel { InvestigationPanel }
import from ..organisms.SecurityPanel { SecurityPanel }
import from ..organisms.SecurityImpactPanel { SecurityImpactPanel }
import from ..organisms.RecoveryPanel { RecoveryPanel }

def:pub SymphonyDashboard -> JsxElement {
    has dashboard: DashboardState | None = None,
        loading: bool = True,
        load_error: str = "",
        selected_incident: str = "normal",
        selected_service: str = "payment",
        incident: PanelStatus = PanelStatus(),
        investigation: InvestigationView = InvestigationView(),
        scan: ScanView = ScanView(),
        impact: ImpactView = ImpactView(),
        recovery: RecoveryView = RecoveryView(),
        assessment: SecurityAssessmentView = SecurityAssessmentView(),
        proposal: RecoveryProposalView = RecoveryProposalView(),
        discovered: list[Dependency | DependencyView] = [],
        findings: dict[str, int] = {};
    # Mutable lifecycle state must remain current across awaits on Jac 0.34.19.
    has request_scope: Ref[RequestScope] = Ref(RequestScope());

    async can with entry {
        await loadDashboard();
    }

    async def loadDashboard -> None;
    def clearResults -> None;
    def selectService(service_id: str) -> None;
    async def changeIncident(reset: bool = False) -> None;
    async def triggerIncident -> None {
        await changeIncident();
    }
    async def resetSimulation -> None {
        await changeIncident(True);
    }
    async def investigate -> None {
        await perform("investigation");
    }
    async def scanDependencies -> None {
        await perform("scan");
    }
    async def analyzeImpact -> None {
        await perform("impact");
    }
    async def previewRecovery -> None {
        await perform("recovery");
    }
    async def assessRisk -> None {
        await perform("security_analysis");
    }
    async def proposeRecovery -> None {
        await perform("recovery_agent");
    }
    def setFeedback(operation: str, feedback: PanelStatus) -> None;
    async def perform(operation: str) -> None;

    edges = merge_dependencies(dashboard.dependencies, discovered) if dashboard else [];
    changing = is_busy(incident.status);
    return
        <div className="app-shell">
            <a className="skip-link" href="#dashboard-main">Skip to dashboard</a>
            <TopBar/>
            <main className="workspace" id="dashboard-main">
                {loading
                and <div className="loading-state" role="status">
                    Loading service topology…
                </div>}{load_error
                and <div className="error-state" role="alert">
                    <p>{load_error}</p>
                    <ActionButton
                        label="Retry dashboard"
                        on_click={loadDashboard}
                        busy={loading}
                    />
                </div>}{dashboard
                and <>
                    <SystemOverview
                        summary={overview_summary(dashboard, edges, findings)}
                        run_id={dashboard.simulation_run_id}
                    />
                    <section className="dashboard-grid">
                        <DependencyGraph
                            services={dashboard.services}
                            dependencies={edges}
                            selected_service={selected_service}
                            on_select={selectService}
                        />
                        <IncidentPanel
                            selected_incident={selected_incident}
                            feedback={incident}
                            on_incident_change={lambda (selected: str) { selected_incident = selected; }}
                            on_trigger={triggerIncident}
                            on_reset={resetSimulation}
                            on_investigate={investigate}
                            investigation_busy={is_busy(investigation.feedback.status)}
                        />
                        <InvestigationPanel result={investigation}/>
                        <SecurityPanel
                            services={dashboard.services}
                            selected_service={selected_service}
                            result={scan}
                            disabled={changing}
                            on_service_change={selectService}
                            on_scan={scanDependencies}
                            assessment={assessment}
                            rule_priority={impact.priority
                                if impact.priority != "unknown"
                                else assessment.rule_priority}
                            on_assess={assessRisk}
                        />
                        <SecurityImpactPanel
                            result={impact}
                            service_id={selected_service}
                            disabled={changing}
                            on_analyze={analyzeImpact}
                        />
                        <RecoveryPanel
                            result={recovery}
                            service_id={selected_service}
                            disabled={changing}
                            on_preview={previewRecovery}
                            proposal={proposal}
                            proposal_disabled={is_busy(investigation.feedback.status)}
                            on_propose={proposeRecovery}
                        />
                    </section>
                </>}
            </main>
        </div>;
}
