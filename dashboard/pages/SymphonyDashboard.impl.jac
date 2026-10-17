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
    scope = request_scope.current;
    if scope is None {
        return;
    }
    if service_id == scope.selected_service {
        return;
    }
    selected_service = service_id;
    scope.selected_service = service_id;
    scan = ScanView();
    impact = ImpactView();
    recovery = RecoveryView();
    scope.request_ids = {
        ** scope.request_ids,
        "scan": scope.request_ids["scan"] + 1,
        "impact": scope.request_ids["impact"] + 1,
        "recovery": scope.request_ids["recovery"] + 1
    };
}

impl SymphonyDashboard.loadDashboard -> None {
    scope = request_scope.current;
    if scope is None {
        return;
    }
    scope.load_request += 1;
    ticket = scope.load_request;
    epoch = scope.generation;
    loading = True;
    load_error = "";
    try {
        __jacClearCache();
        snapshot = await get_dashboard_state();
        if not dashboard_is_valid(snapshot) {
            raise ValueError("Invalid dashboard response");
        }
        if ticket != scope.load_request or epoch != scope.generation {
            return;
        }
        if scope.run_id and scope.run_id != snapshot.simulation_run_id {
            scope.generation += 1;
            clearResults();
            incident = PanelStatus(
                message="The simulation changed. Previous-run results were cleared."
            );
        }
        dashboard = snapshot;
        scope.run_id = snapshot.simulation_run_id;
    } except Exception {
        if ticket == scope.load_request and epoch == scope.generation {
            load_error = "Dashboard state could not be loaded. Check the server and retry.";
        }
    } finally {
        if ticket == scope.load_request {
            loading = False;
        }
    }
}

impl SymphonyDashboard.changeIncident(reset: bool = False) -> None {
    scope = request_scope.current;
    if scope is None {
        return;
    }
    if scope.changing {
        return;
    }
    scope.changing = True;
    scope.generation += 1;
    scope.load_request += 1;
    loading = False;
    epoch = scope.generation;
    clearResults();
    load_error = "";
    incident = PanelStatus(
        status="loading",
        message="Resetting the simulation…"
            if reset
            else "Applying the selected incident…"
    );
    try {
        __jacClearCache();
        result = await reset_incident()
            if reset
            else await start_incident(selected_incident);
        if epoch != scope.generation {
            return;
        }
        incident = status_view(result);
        if has_result(result.status) {
            __jacClearCache();
            snapshot = await get_dashboard_state();
            if not dashboard_is_valid(snapshot) {
                raise ValueError("Invalid dashboard response");
            }
            if epoch != scope.generation {
                return;
            }
            dashboard = snapshot;
            scope.run_id = snapshot.simulation_run_id;
            incident = PanelStatus(
                status=result.status,
                message="Simulation reset. Previous-run results cleared."
                    if reset
                    else "Incident applied. Service health refreshed."
            );
        }
    } except Exception {
        if epoch == scope.generation {
            incident = PanelStatus(
                status="failed",
                message="The incident request or topology refresh failed. Retry before relying on the displayed state."
            );
        }
    } finally {
        if epoch == scope.generation {
            scope.changing = False;
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
    scope = request_scope.current;
    if scope is None {
        return;
    }
    if dashboard is None or scope.changing {
        return;
    }
    epoch = scope.generation;
    run_id = scope.run_id;
    service_id = "" if operation == "investigation" else scope.selected_service;
    scope.request_ids[operation] += 1;
    ticket = scope.request_ids[operation];
    setFeedback(operation, PanelStatus(status="loading"));
    try {
        # Jac 0.34.19 treats indirect feature adapters as cacheable readers.
        # User actions and run-validation snapshots require fresh responses.
        __jacClearCache();
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
        active_service = "" if operation == "investigation" else scope.selected_service;
        if not request_is_current(
            epoch,
            scope.generation,
            ticket,
            scope.request_ids[operation],
            service_id,
            active_service,
            run_id,
            scope.run_id,
            ""
        ) {
            return;
        }
        # Refresh after long operations to detect a run changed by another caller.
        __jacClearCache();
        snapshot = await get_dashboard_state();
        if not dashboard_is_valid(snapshot) {
            raise ValueError("Invalid dashboard response");
        }
        if epoch != scope.generation or ticket != scope.request_ids[operation] {
            return;
        }
        if snapshot.simulation_run_id != run_id {
            scope.generation += 1;
            clearResults();
            dashboard = snapshot;
            scope.run_id = snapshot.simulation_run_id;
            incident = PanelStatus(
                message="The simulation changed. Stale operation results were discarded."
            );
            return;
        }
        active_service = "" if operation == "investigation" else scope.selected_service;
        if not request_is_current(
            epoch,
            scope.generation,
            ticket,
            scope.request_ids[operation],
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
        scope.run_id = snapshot.simulation_run_id;
        if operation == "investigation" {
            next_investigation = investigation_view(result);
            investigation = next_investigation;
            if has_result(next_investigation.feedback.status) {
                discovered = merge_dependencies(
                    discovered, next_investigation.dependencies
                );
            }
        } elif operation == "scan" {
            next_scan = scan_view(result, service_id);
            scan = next_scan;
            if has_result(next_scan.feedback.status) {
                next_findings = {** findings};
                next_findings[service_id] = next_scan.finding_count;
                findings = next_findings;
            }
        } elif operation == "impact" {
            impact = impact_view(result);
        } else {
            recovery = recovery_view(result);
        }
    } except Exception {
        active_service = "" if operation == "investigation" else scope.selected_service;
        if request_is_current(
            epoch,
            scope.generation,
            ticket,
            scope.request_ids[operation],
            service_id,
            active_service,
            run_id,
            scope.run_id,
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
