"""Stable public operation surface; feature implementations bind through integration/."""
import from contracts { DashboardState, OperationEnvelope }
import from integration.gateway { read_dashboard, invoke }
import from integration.ports { configure_ports }
import from integration.bindings { production_ports }
import from integration.automation {
    run_full_assessment_impl,
    latest_full_assessment_impl,
    monitoring_alert_impl
}

with entry {
    configure_ports(production_ports());
}

def:pub get_dashboard_state -> DashboardState {
    return read_dashboard();
}

def:pub start_incident(incident_id: str) -> OperationEnvelope {
    return invoke("start_incident", {"incident_id": incident_id});
}

def:pub reset_incident -> OperationEnvelope {
    return invoke("reset_incident", {});
}

def:pub check_service_health(service_id: str) -> OperationEnvelope {
    return invoke("check_service_health", {"service_id": service_id});
}

def:pub get_service_logs(service_id: str) -> OperationEnvelope {
    return invoke("get_service_logs", {"service_id": service_id});
}

def:pub trace_requests(service_id: str) -> OperationEnvelope {
    return invoke("trace_requests", {"service_id": service_id});
}

def:pub run_investigation -> OperationEnvelope {
    return invoke("run_investigation", {});
}

def:pub scan_service_dependencies(service_id: str) -> OperationEnvelope {
    return invoke("scan_service_dependencies", {"service_id": service_id});
}

def:pub analyze_security_impact(service_id: str) -> OperationEnvelope {
    return invoke("analyze_security_impact", {"service_id": service_id});
}

def:pub preview_recovery(service_id: str) -> OperationEnvelope {
    return invoke("preview_recovery", {"service_id": service_id});
}

def:pub run_security_analysis(service_id: str) -> OperationEnvelope {
    return invoke("run_security_analysis", {"service_id": service_id});
}

def:pub run_recovery_agent -> OperationEnvelope {
    return invoke("run_recovery_agent", {});
}

def:pub run_full_assessment(
    trigger: str = "manual", service_id: str = "", force: bool = False
) -> OperationEnvelope {
    return run_full_assessment_impl(trigger, service_id, force);
}

def:pub get_latest_full_assessment -> OperationEnvelope {
    return latest_full_assessment_impl();
}

def:pub monitoring_alert(
    service_id: str, state: str, token: str = ""
) -> OperationEnvelope {
    return monitoring_alert_impl(service_id, state, token);
}
