"""Async handlers for the SYMPHONY dashboard shell."""

impl SymphonyDashboard.loadDashboard{
    try {
        dashboard = await get_dashboard_state();
    } except Exception as error {
        load_error = f"Dashboard state could not be loaded: {error}";
    } finally {
        loading = False;
    }
}

impl SymphonyDashboard.triggerIncident{
    operation_busy = True;
    try {
        result = await start_incident(selected_incident);
        operation_status = result.error.message if result.error else result.status;
    } except Exception as error {
        operation_status = f"Incident request failed: {error}";
    } finally {
        operation_busy = False;
    }
}

impl SymphonyDashboard.resetSimulation{
    operation_busy = True;
    try {
        result = await reset_incident();
        operation_status = result.error.message if result.error else result.status;
    } except Exception as error {
        operation_status = f"Reset request failed: {error}";
    } finally {
        operation_busy = False;
    }
}

impl SymphonyDashboard.investigate{
    operation_busy = True;
    try {
        result = await run_investigation();
        operation_status = result.error.message if result.error else result.status;
    } except Exception as error {
        operation_status = f"Investigation request failed: {error}";
    } finally {
        operation_busy = False;
    }
}

impl SymphonyDashboard.scanDependencies{
    operation_busy = True;
    try {
        result = await scan_service_dependencies(selected_service);
        operation_status = result.error.message if result.error else result.status;
    } except Exception as error {
        operation_status = f"OSV scan request failed: {error}";
    } finally {
        operation_busy = False;
    }
}
