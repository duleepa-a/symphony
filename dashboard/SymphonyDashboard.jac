"""Stateful dashboard shell."""

import type from ..contracts { DashboardState }
import from ..operations {
    get_dashboard_state,
    start_incident,
    reset_incident,
    run_investigation,
    scan_service_dependencies
}
import from .TopBar { TopBar }
import from .SystemOverview { SystemOverview }
import from .DependencyGraph { DependencyGraph }
import from .IncidentPanel { IncidentPanel }
import from .InvestigationPanel { InvestigationPanel }
import from .SecurityPanel { SecurityPanel }
import from .RecoveryPanel { RecoveryPanel }

def:pub SymphonyDashboard() -> JsxElement {
    has dashboard: DashboardState | None = None,
        loading: bool = True,
        load_error: str = "",
        selected_incident: str = "normal",
        selected_service: str = "payment",
        operation_status: str = "Foundation ready. Live integrations are clearly marked.",
        operation_busy: bool = False;

    can with entry {
        loadDashboard();
    }

    async def loadDashboard;
    async def triggerIncident;
    async def resetSimulation;
    async def investigate;
    async def scanDependencies;

    return <div className="app-shell">
        <TopBar/>
        <main className="workspace">
            {loading
                and <div className="loading-state">Loading service topology…</div>}{load_error
                and <div className="error-state">{load_error}</div>}{dashboard
                and <>
                    <SystemOverview summary={dashboard.summary}/>
                    <section className="dashboard-grid">
                        <DependencyGraph services={dashboard.services}/>
                        <IncidentPanel
                            selected_incident={selected_incident}
                            busy={operation_busy}
                            on_incident_change={lambda (value: str) { selected_incident = value; }}
                            on_trigger={triggerIncident}
                            on_reset={resetSimulation}
                            on_investigate={investigate}
                        />
                        <InvestigationPanel status={operation_status}/>
                        <SecurityPanel
                            services={dashboard.services}
                            selected_service={selected_service}
                            busy={operation_busy}
                            on_service_change={lambda (value: str) { selected_service = value; }}
                            on_scan={scanDependencies}
                        />
                        <RecoveryPanel/>
                    </section>
                </>}
        </main>
    </div>;
}
