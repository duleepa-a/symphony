"""Development-only fixture entry; never deploy this application."""
import from operations {
    get_dashboard_state,
    start_incident,
    reset_incident,
    check_service_health,
    get_service_logs,
    trace_requests,
    run_investigation,
    scan_service_dependencies,
    analyze_security_impact,
    preview_recovery,
    run_security_analysis,
    run_recovery_agent
}
import from tests.dashboard_preview_server { fixture_mode }
import from .tests.dashboard_preview { FixtureToolbar }
import from .dashboard.pages.SymphonyDashboard { SymphonyDashboard }
import "./styles.css";

def:pub app -> JsxElement {
    return
        <>
            <FixtureToolbar/>
            <SymphonyDashboard/>
        </>;
}
