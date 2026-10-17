"""Serialize short simulator operations; never hold this lock over network or model calls."""
sv {
    import from threading { RLock }
    import from contracts { DashboardState, OperationEnvelope }
    import from simulation.state { sim_dashboard_state }
    glob simulation_lock = RLock();
    def dashboard() -> DashboardState {
        with simulation_lock {
            return sim_dashboard_state();
        }
    }
    def simulation_call(
        handler: Callable[..., OperationEnvelope], arguments: dict[str, any]
    ) -> OperationEnvelope {
        with simulation_lock {
            return handler(**arguments);
        }
    }
}
