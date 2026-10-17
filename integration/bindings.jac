"""Production composition root: explicit feature exports, never diagnostic fixtures."""
sv {
    import from integration.ports { FeaturePorts }
    import from integration.simulation_adapter { dashboard, simulation_call }
    import from integration.security_adapter { scan }
    import from integration.investigation_adapter { investigate }
    import from simulation.state { sim_start_incident, sim_reset }
    import from simulation.diagnostics {
        sim_check_health,
        sim_get_logs,
        sim_trace_requests
    }
    import from simulation.impact { sim_analyze_impact }
    import from simulation.recovery { sim_preview_recovery }
    import from contracts { OperationEnvelope }

    def impact(service_id: str) -> OperationEnvelope {
        # Keep potential_exposure as a list for agent consumers; the dashboard joins it.
        return simulation_call(sim_analyze_impact, {"service_id": service_id});
    }
    def start(incident_id: str) -> OperationEnvelope {
        return simulation_call(sim_start_incident, {"incident_id": incident_id});
    }
    def reset() -> OperationEnvelope {
        return simulation_call(sim_reset, {});
    }
    def health(service_id: str) -> OperationEnvelope {
        return simulation_call(sim_check_health, {"service_id": service_id});
    }
    def logs(service_id: str) -> OperationEnvelope {
        return simulation_call(sim_get_logs, {"service_id": service_id});
    }
    def traces(service_id: str) -> OperationEnvelope {
        return simulation_call(sim_trace_requests, {"service_id": service_id});
    }
    def recovery(service_id: str) -> OperationEnvelope {
        return simulation_call(sim_preview_recovery, {"service_id": service_id});
    }
    def production_ports() -> FeaturePorts {
        return FeaturePorts(
            dashboard=dashboard,
            handlers={
                "start_incident": start,
                "reset_incident": reset,
                "check_service_health": health,
                "get_service_logs": logs,
                "trace_requests": traces,
                "run_investigation": investigate,
                "scan_service_dependencies": scan,
                "analyze_security_impact": impact,
                "preview_recovery": recovery
            }
        );
    }
}
