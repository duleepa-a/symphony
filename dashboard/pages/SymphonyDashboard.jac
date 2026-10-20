"""Page orchestrator: owns state, delegates rendering and boundary decoding."""
import from "@jac/runtime" { __jacClearCache }
import from react { useEffect }
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
    run_recovery_agent,
    run_full_assessment,
    get_latest_full_assessment
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
    ServiceRiskView,
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
    operation_envelope,
    service_states,
    newly_unhealthy,
    request_is_current,
    merge_dependencies,
    overview_summary,
    valid_selection,
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
        automation: PanelStatus = PanelStatus(),
        service_risks: list[ServiceRiskView] = [],
        discovered: list[Dependency | DependencyView] = [],
        findings: dict[str, int] = {},
        request_scope: Ref[RequestScope] = Ref(RequestScope()),
        assessment_busy: Ref[bool] = Ref(False),
        poll_busy: Ref[bool] = Ref(False),
        observed_states: Ref[dict[str, str]] = Ref({}),
        latest_assessment_id: Ref[str] = Ref("");

    useEffect(
        lambda {
            interval = setInterval(lambda { pollHealth(); }, 10000);
            return lambda { clearInterval(interval); };
        },
        []
    );

    async can with entry {
        await loadDashboard();
        await pollHealth();
    }

    async def loadDashboard -> None;
    def clearResults -> None;
    def selectService(service_id: str) -> None;
    async def changeIncident(reset: bool = False) -> None;
    async def triggerIncident {
        await changeIncident();
    }
    async def resetSimulation {
        await changeIncident(True);
    }
    async def investigate {
        await perform("investigation");
    }
    async def scanDependencies {
        await perform("scan");
    }
    async def analyzeImpact {
        await perform("impact");
    }
    async def previewRecovery {
        await perform("recovery");
    }
    async def assessRisk {
        await perform("security_analysis");
    }
    async def proposeRecovery {
        await perform("recovery_agent");
    }
    async def runFullAssessment {
        await assessAll("manual", selected_service, True);
    }
    async def assessAll(
        trigger: str, service_id: str = "", force: bool = False
    ) -> None;
    def applyAssessment(result: OperationEnvelope) -> None;
    async def pollHealth -> None;
    def setFeedback(operation: str, feedback: PanelStatus) -> None;
    async def perform(operation: str) -> None;

    edges = merge_dependencies(dashboard.dependencies, discovered) if dashboard else [];
    changing = is_busy(incident.status) or is_busy(automation.status);
    return
        <div className="app-shell">
            <a className="skip-link" href="#dashboard-main">Skip to dashboard</a>
            <TopBar mode={dashboard.service_mode if dashboard else "loading"}/>
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
                    {dashboard.topology_error
                    and <div className="error-state" role="alert">
                        <p>{dashboard.topology_error}</p>
                    </div>}
                    {not dashboard.services
                    and <div className="loading-state" role="status">
                        No services are registered. Check the service discovery settings.
                    </div>}
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
                            on_full_assessment={runFullAssessment}
                            full_assessment_busy={is_busy(automation.status)}
                            automation_feedback={automation}
                            service_mode={dashboard.service_mode}
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
                            service_risks={service_risks}
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
                            proposal_disabled={is_busy(investigation.feedback.status)
                            or investigation.feedback.status != "completed"
                            or not investigation.evidence}
                            on_propose={proposeRecovery}
                        />
                    </section>
                </>}
            </main>
        </div>;
}
