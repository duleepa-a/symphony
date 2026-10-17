"""SYMPHONY application entry point."""

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

import "./styles.css";
import from .dashboard.pages.SymphonyDashboard { SymphonyDashboard }

def:pub app -> JsxElement {
    return <SymphonyDashboard/>;
}
