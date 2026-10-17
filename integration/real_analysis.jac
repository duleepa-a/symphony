"""Honest impact and recovery previews over observed real-service state."""
sv {
    import from copy { deepcopy }
    import from contracts { OperationEnvelope }
    import from integration.real_provider { real_dashboard }
    import from simulation.impact { sim_analyze_impact }
    import from simulation.state { is_known_service, unknown_service }

    def real_analyze_impact(service_id: str) -> OperationEnvelope {
        impact = sim_analyze_impact(service_id);
        if impact.status != "completed" {
            return impact;
        }
        snapshot = real_dashboard();
        states = {service.id: service.state for service in snapshot.services};
        dependents = impact.data.get("dependent_services", []);
        impact.data = {
            ** impact.data,
            "observed_states": states,
            "potential_exposure": [
                f"{dependent} is currently {states.get(
                    dependent, 'unknown'
                )} and may be operationally affected through its dependency chain; this does not establish a vulnerability in that service."
                for dependent in dependents
            ],
            "analysis_source": "real_service_health",
            "simulation_run_id": snapshot.simulation_run_id
        };
        return impact;
    }

    def real_preview_recovery(
        service_id: str, action: str = "restart_or_redeploy"
    ) -> OperationEnvelope {
        if not is_known_service(service_id) {
            return unknown_service(service_id);
        }
        snapshot = real_dashboard();
        observed = [
            {"id": service.id, "state": service.state} for service in snapshot.services
        ];
        return OperationEnvelope(
            status="completed",
            data={
                "service_id": service_id,
                "action": action,
                "candidate_repair": f"{action} {service_id}, then verify its /health endpoint and affected dependents.",
                "before": observed,
                "after": deepcopy(observed),
                "outcome": "not_applied",
                "analysis_source": "real_service_health",
                "verification_note": "Symphony does not mutate Docker services. After-state remains the latest observation until an operator applies the repair.",
                "simulation_run_id": snapshot.simulation_run_id
            }
        );
    }
}
