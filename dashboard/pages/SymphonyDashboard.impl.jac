"""Async use cases: run-scoped and request-scoped commits to presentation state."""

impl SymphonyDashboard.clearResults -> None {
    investigation = InvestigationView();
    scan = ScanView();
    impact = ImpactView();
    recovery = RecoveryView();
    discovered = [];
    findings = {};
}

impl SymphonyDashboard.selectService(service_id: str) -> None {
    if service_id == selected_service {
        return;
    }
    selected_service = service_id;
    scan = ScanView();
    impact = ImpactView();
    recovery = RecoveryView();
    request_ids = {
        ** request_ids,
        "scan": request_ids["scan"] + 1,
        "impact": request_ids["impact"] + 1,
        "recovery": request_ids["recovery"] + 1
    };
}

impl SymphonyDashboard.loadDashboard -> None {
    load_request += 1;
    ticket = load_request;
    epoch = generation;
    loading = True;
    load_error = "";
    try {
        snapshot = await get_dashboard_state();
        if ticket != load_request or epoch != generation {
            return;
        }
        if dashboard and dashboard.simulation_run_id != snapshot.simulation_run_id {
            generation += 1;
            clearResults();
            incident = PanelStatus(
                message="The simulation changed. Previous-run results were cleared."
            );
        }
        dashboard = snapshot;
    } except Exception {
        if ticket == load_request and epoch == generation {
            load_error = "Dashboard state could not be loaded. Check the server and retry.";
        }
    } finally {
        if ticket == load_request {
            loading = False;
        }
    }
}

impl SymphonyDashboard.changeIncident(reset: bool = False) -> None {
    if is_busy(incident.status) {
        return;
    }
    generation += 1;
    load_request += 1;
    loading = False;
    epoch = generation;
    clearResults();
    load_error = "";
    incident = PanelStatus(
        status="loading",
        message="Resetting the simulation…"
            if reset
            else "Applying the selected incident…"
    );
    try {
        result = await reset_incident()
            if reset
            else await start_incident(selected_incident);
        if epoch != generation {
            return;
        }
        incident = status_view(result);
        if has_result(result.status) {
            snapshot = await get_dashboard_state();
            if epoch != generation {
                return;
            }
            dashboard = snapshot;
            incident = PanelStatus(
                status=result.status,
                message="Simulation reset. Previous-run results cleared."
                    if reset
                    else "Incident applied. Service health refreshed."
            );
        }
    } except Exception {
        if epoch == generation {
            incident = PanelStatus(
                status="failed",
                message="The incident request or topology refresh failed. Retry before relying on the displayed state."
            );
        }
    }
}

impl SymphonyDashboard.setFeedback(operation: str, feedback: PanelStatus) -> None {
    if operation == "investigation" {
        investigation = InvestigationView(feedback=feedback);
    } elif operation == "scan" {
        scan = ScanView(feedback=feedback, service_id=selected_service);
    } elif operation == "impact" {
        impact = ImpactView(feedback=feedback);
    } else {
        recovery = RecoveryView(feedback=feedback);
    }
}

impl SymphonyDashboard.perform(operation: str) -> None {
    if dashboard is None or is_busy(incident.status) {
        return;
    }
    epoch = generation;
    run_id = dashboard.simulation_run_id;
    service_id = "" if operation == "investigation" else selected_service;
    request_ids = {** request_ids, operation: request_ids[operation] + 1};
    ticket = request_ids[operation];
    setFeedback(operation, PanelStatus(status="loading"));
    try {
        result: OperationEnvelope;
        if operation == "investigation" {
            result = await run_investigation();
        } elif operation == "scan" {
            result = await scan_service_dependencies(service_id);
        } elif operation == "impact" {
            result = await analyze_security_impact(service_id);
        } else {
            result = await preview_recovery(service_id);
        }
        active_service = "" if operation == "investigation" else selected_service;
        if not request_is_current(
            epoch,
            generation,
            ticket,
            request_ids[operation],
            service_id,
            active_service,
            run_id,
            dashboard.simulation_run_id,
            ""
        ) {
            return;
        }
        # Refresh after long operations to detect a run changed by another caller.
        snapshot = await get_dashboard_state();
        if epoch != generation or ticket != request_ids[operation] {
            return;
        }
        if snapshot.simulation_run_id != run_id {
            generation += 1;
            clearResults();
            dashboard = snapshot;
            incident = PanelStatus(
                message="The simulation changed. Stale operation results were discarded."
            );
            return;
        }
        active_service = "" if operation == "investigation" else selected_service;
        if not request_is_current(
            epoch,
            generation,
            ticket,
            request_ids[operation],
            service_id,
            active_service,
            run_id,
            snapshot.simulation_run_id,
            text(value(result.data, "simulation_run_id", ""))
        ) {
            setFeedback(
                operation,
                PanelStatus(
                    status="failed",
                    message="Results belong to an earlier simulation. Run the operation again."
                )
            );
            return;
        }
        dashboard = snapshot;
        if operation == "investigation" {
            investigation = investigation_view(result);
            if has_result(investigation.feedback.status) {
                discovered = merge_dependencies(discovered, investigation.dependencies);
            }
        } elif operation == "scan" {
            scan = scan_view(result, service_id);
            if has_result(scan.feedback.status) {
                findings = {** findings, service_id: scan.finding_count};
            }
        } elif operation == "impact" {
            impact = impact_view(result);
        } else {
            recovery = recovery_view(result);
        }
    } except Exception {
        active_service = "" if operation == "investigation" else selected_service;
        if request_is_current(
            epoch,
            generation,
            ticket,
            request_ids[operation],
            service_id,
            active_service,
            run_id,
            dashboard.simulation_run_id,
            ""
        ) {
            setFeedback(
                operation,
                PanelStatus(
                    status="failed",
                    message="The request failed. No successful result has been assumed. Retry the operation."
                )
            );
        }
    }
}
