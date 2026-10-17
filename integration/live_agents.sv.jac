"""Adapt the completed feature exports to the application session ports."""
sv {
    import from contracts { OperationEnvelope }
    import from integration.agent_ports { AgentPorts, AgentSession }
    import from integration.simulation_adapter { simulation_call }
    import from security_analyst.agent { run_security_analysis_impl }
    import from recovery_agent.agent { run_recovery_agent_impl }
    import from simulation.recovery { sim_list_repair_options, sim_preview_repair }
    import from integration.service_provider { is_real_mode }
    import from integration.real_analysis { real_preview_recovery }

    def security_runner(session: AgentSession) -> OperationEnvelope {
        scan: OperationEnvelope = session.read("scan_results");
        return run_security_analysis_impl(
            session.service_id, scan, session.simulation_run_id
        );
    }
    def recovery_runner(session: AgentSession) -> OperationEnvelope {
        investigation: OperationEnvelope = session.read("investigation_result");
        return run_recovery_agent_impl(investigation.data, session.simulation_run_id);
    }
    def repair_options -> list[str] {
        result = simulation_call(sim_list_repair_options, {});
        if result.status != "completed" {
            raise RuntimeError("Repair options are unavailable.");
        }
        return [item["action"] for item in result.data["options"]];
    }
    def preview_action(service_id: str, action: str) -> OperationEnvelope {
        if is_real_mode() {
            return real_preview_recovery(service_id, action);
        }
        return simulation_call(
            sim_preview_repair, {"service_id": service_id, "action": action}
        );
    }
    def live_agent_ports -> AgentPorts {
        return AgentPorts(
            security=security_runner,
            recovery=recovery_runner,
            repair_options=repair_options,
            preview=preview_action
        );
    }
}
