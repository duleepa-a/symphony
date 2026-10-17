"""Page orchestrator: owns state, delegates rendering and boundary decoding."""
import type from ...contracts { DashboardState, Dependency, OperationEnvelope }
import from ...operations {
    get_dashboard_state,
    start_incident,
    reset_incident,
    run_investigation,
    scan_service_dependencies,
    analyze_security_impact,
    preview_recovery
}
import from ..models.view_models {
    PanelStatus,
    ScanView,
    InvestigationView,
    ImpactView,
    RecoveryView,
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
        discovered: list[Dependency] = [],
        findings: dict[str, int] = {},
        generation: int = 0,
        load_request: int = 0,
        request_ids: dict[str, int] = {
            "investigation": 0,
            "scan": 0,
            "impact": 0,
            "recovery": 0
        };

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
    def setFeedback(operation: str, feedback: PanelStatus) -> None;
    async def perform(operation: str) -> None;

    edges = merge_dependencies(dashboard.dependencies, discovered) if dashboard else [];
    changing = is_busy(incident.status);
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
                        />
                    </section>
                </>}
        </main>
    </div>
}
