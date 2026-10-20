"""Mode-aware view of the active run: the simulator in mock mode, real observations otherwise.

Agents and adapters ask this module which run is current and what the system
looks like, so they never read simulator state while real services are in use.
"""
sv {
    import from contracts { DashboardState, OperationEnvelope }
    import from integration.service_provider { is_real_mode }
    import from integration.real_provider { real_dashboard }
    import from integration.real_store { current_real_run_id, lookup_real_evidence }
    import from simulation.state {
        accept_dependency,
        sim_accept_discovered_dependency,
        sim_dashboard_state,
        sim_is_current_run
    }

    def current_dashboard -> DashboardState {
        return real_dashboard() if is_real_mode() else sim_dashboard_state();
    }

    def is_current_run(run_id: str) -> bool {
        if is_real_mode() {
            return run_id == current_real_run_id();
        }
        return sim_is_current_run(run_id);
    }

    def accept_discovered_dependency(
        source_id: str, target_id: str, evidence_ids: list[str]
    ) -> OperationEnvelope {
        if is_real_mode() {
            return accept_dependency(
                source_id,
                target_id,
                evidence_ids,
                lookup_real_evidence,
                current_real_run_id()
            );
        }
        return sim_accept_discovered_dependency(source_id, target_id, evidence_ids);
    }
}
