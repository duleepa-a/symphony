"""Production composition root: explicit feature exports, routing via provider mode."""
sv {
    import from integration.ports { FeaturePorts }
    import from integration.agent_ports { AgentPorts }
    import from integration.live_agents { live_agent_ports }
    import from integration.agent_adapter { security_analysis, recovery_analysis }
    import from integration.simulation_adapter { dashboard, simulation_call }
    import from integration.security_adapter { scan }
    import from integration.investigation_adapter { investigate }
    import from integration.service_provider { is_real_mode }
    import from integration.real_provider {
        real_check_health,
        real_dashboard,
        real_get_logs,
        real_trace_requests
    }
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
    def reset -> OperationEnvelope {
        return simulation_call(sim_reset, {});
    }
    def health(service_id: str) -> OperationEnvelope {
        if is_real_mode() {
            return real_check_health(service_id);
        }
        return simulation_call(sim_check_health, {"service_id": service_id});
    }
    def logs(service_id: str) -> OperationEnvelope {
        if is_real_mode() {
            return real_get_logs(service_id);
        }
        return simulation_call(sim_get_logs, {"service_id": service_id});
    }
    def traces(service_id: str) -> OperationEnvelope {
        if is_real_mode() {
            return real_trace_requests(service_id);
        }
        return simulation_call(sim_trace_requests, {"service_id": service_id});
    }
    def recovery(service_id: str) -> OperationEnvelope {
        return simulation_call(sim_preview_recovery, {"service_id": service_id});
    }
    def production_ports(agents: AgentPorts | None = None) -> FeaturePorts {
        configured = agents if agents is not None else live_agent_ports();
        def security_agent(service_id: str) -> OperationEnvelope {
            return security_analysis(service_id, configured);
        }
        def recovery_agent() -> OperationEnvelope {
            return recovery_analysis(configured);
        }
        return FeaturePorts(
            dashboard=real_dashboard if is_real_mode() else dashboard,
            handlers={
                "start_incident": start,
                "reset_incident": reset,
                "check_service_health": health,
                "get_service_logs": logs,
                "trace_requests": traces,
                "run_investigation": investigate,
                "scan_service_dependencies": scan,
                "analyze_security_impact": impact,
                "preview_recovery": recovery,
                "run_security_analysis": security_agent,
                "run_recovery_agent": recovery_agent
            }
        );
    }
}
