"""Async use cases: run-scoped and request-scoped commits to presentation state."""

impl SymphonyDashboard.clearResults -> None {
    assessment = SecurityAssessmentView();
    proposal = RecoveryProposalView();
    investigation = InvestigationView();
    scan = ScanView();
    impact = ImpactView();
    recovery = RecoveryView();
    discovered = [];
    findings = {};
    service_risks = [];
}

impl SymphonyDashboard.applyAssessment(result: OperationEnvelope) -> None {
    automation = status_view(result);
    if not has_result(result.status) {
        return;
    }
    if bool(value(result.data, "skipped", False)) {
        automation = PanelStatus(
            status="completed",
            message=text(
                value(result.data, "reason", "No service requires assessment.")
            )
        );
        return;
    }
    assessment_id = text(value(result.data, "assessment_id", ""));
    if assessment_id {
        latest_assessment_id.current = assessment_id;
    }
    target = text(value(result.data, "primary_service_id", selected_service));
    if target {
        selected_service = target;
        scope = request_scope.current;
        if scope is not None {
            scope.selected_service = target;
        }
    }

    next_risks: list[ServiceRiskView] = [];
    next_findings = {** findings};
    for item in value(result.data, "service_assessments", []) {
        scan_step = value(item, "scan", {});
        analyst_step = value(item, "security_analysis", {});
        service_id = text(value(item, "service_id", ""));
        count = int(value(item, "finding_count", 0));
        next_risks.append(
            ServiceRiskView(
                service_id=service_id,
                service_name=text(value(item, "service_name", service_id)),
                scan_status=text(value(scan_step, "status", "failed")),
                assessment_status=text(value(analyst_step, "status", "failed")),
                finding_count=count,
                high_finding_count=int(value(item, "high_finding_count", 0)),
                priority=text(value(item, "analyst_priority", "unknown"))
            )
        );
        next_findings[service_id] = count;
    }
    if next_risks {
        service_risks = next_risks;
        findings = next_findings;
    }

    investigation_result = operation_envelope(value(result.data, "investigation", {}));
    next_investigation = investigation_view(investigation_result);
    investigation = next_investigation;
    if has_result(next_investigation.feedback.status) {
        discovered = merge_dependencies(discovered, next_investigation.dependencies);
    }

    scan_result = operation_envelope(value(result.data, "scan", {}));
    next_scan = scan_view(scan_result, target);
    scan = next_scan;
    if has_result(next_scan.feedback.status) {
        selected_findings = {** findings};
        selected_findings[target] = next_scan.finding_count;
        findings = selected_findings;
    }
    impact = impact_view(operation_envelope(value(result.data, "impact", {})));
    assessment = security_assessment_view(
        operation_envelope(value(result.data, "security_analysis", {}))
    );
    recovery = recovery_view(operation_envelope(value(result.data, "recovery", {})));
    proposal = recovery_proposal_view(
        operation_envelope(value(result.data, "recovery_agent", {}))
    );
    automation = PanelStatus(
        status=result.status,
        message=f"Full assessment completed for {target}."
            if result.status == "completed"
            else f"Full assessment completed partially for {target}; review step-level errors."
    );
}

impl SymphonyDashboard.assessAll(
    trigger: str, service_id: str = "", force: bool = False
) -> None {
    if bool(assessment_busy.current) {
        return;
    }
    assessment_busy.current = True;
    automation = PanelStatus(
        status="loading",
        message="Collecting diagnostics, vulnerabilities, impact, and recovery guidance…"
    );
    try {
        __jacClearCache();
        result = await run_full_assessment(trigger, service_id, force);
        applyAssessment(result);
        __jacClearCache();
        snapshot = await get_dashboard_state();
        if dashboard_is_valid(snapshot) {
            dashboard = snapshot;
            observed_states.current = service_states(snapshot);
            scope = request_scope.current;
            if scope is not None {
                scope.run_id = snapshot.simulation_run_id;
            }
        }
    } except Exception {
        automation = PanelStatus(
            status="failed",
            message="The full assessment could not complete. Existing results were not treated as current."
        );
    } finally {
        assessment_busy.current = False;
    }
}

impl SymphonyDashboard.pollHealth -> None {
    if bool(poll_busy.current) or bool(assessment_busy.current) {
        return;
    }
    poll_busy.current = True;
    try {
        __jacClearCache();
        snapshot = await get_dashboard_state();
        if not dashboard_is_valid(snapshot) {
            raise ValueError("Invalid dashboard response");
        }
        previous = observed_states.current or {};
        current = service_states(snapshot);
        failures = newly_unhealthy(previous, current);
        unhealthy = [
            service_id
            for (service_id, state) in current.items()
            if state in ["down", "degraded"]
        ];
        first_observation = not bool(previous);
        changed_with_active_failure = bool(previous)
        and previous != current
        and bool(unhealthy);
        observed_states.current = current;
        dashboard = snapshot;
        scope = request_scope.current;
        if scope is not None {
            scope.run_id = snapshot.simulation_run_id;
        }
        if failures or changed_with_active_failure {
            await assessAll("page_detection" if first_observation else "health_change");
        } else {
            __jacClearCache();
            latest = await get_latest_full_assessment();
            incoming_id = text(value(latest.data, "assessment_id", ""));
            if has_result(latest.status)
            and incoming_id
            and incoming_id != latest_assessment_id.current {
                applyAssessment(latest);
            }
        }
    } except Exception {
        # Polling failures do not replace the last known dashboard or manual controls.
        if dashboard is None {
            load_error = "Dashboard polling failed. Check the server and retry.";
        }
    } finally {
        poll_busy.current = False;
    }
}

impl SymphonyDashboard.selectService(service_id: str) -> None {
    scope = request_scope.current;
    if scope is None {
        return;
    }
    if service_id == scope.selected_service {
        return;
    }
    assessment = SecurityAssessmentView();
    scope.request_ids["security_analysis"] += 1;
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
    } elif operation == "security_analysis" {
        assessment = SecurityAssessmentView(feedback=feedback);
    } elif operation == "recovery_agent" {
        proposal = RecoveryProposalView(feedback=feedback);
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
    service_id = ""
        if operation in ["investigation", "recovery_agent"]
        else scope.selected_service;
    scope.request_ids[operation] += 1;
    ticket = scope.request_ids[operation];
    if operation == "scan" {
        scope.request_ids["security_analysis"] += 1;
        assessment = SecurityAssessmentView();
    }
    if operation == "investigation" {
        scope.request_ids["recovery_agent"] += 1;
        proposal = RecoveryProposalView();
    }
    fallback_ticket = scope.request_ids["impact"];
    fallback: OperationEnvelope | None = None;
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
        } elif operation == "security_analysis" {
            result = await run_security_analysis(service_id);
            __jacClearCache();
            try {
                fallback = await analyze_security_impact(service_id);
            } except Exception {
                fallback = None;
            }
        } elif operation == "recovery_agent" {
            result = await run_recovery_agent();
        } else {
            result = await preview_recovery(service_id);
        }
        active_service = ""
            if operation in ["investigation", "recovery_agent"]
            else scope.selected_service;
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
        active_service = ""
            if operation in ["investigation", "recovery_agent"]
            else scope.selected_service;
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
        } elif operation == "security_analysis" {
            assessment = security_assessment_view(result);
            if fallback is not None
            and fallback_ticket == scope.request_ids["impact"] {
                impact = impact_view(fallback);
            }
        } elif operation == "recovery_agent" {
            proposal = recovery_proposal_view(result);
        } else {
            recovery = recovery_view(result);
        }
    } except Exception {
        active_service = ""
            if operation in ["investigation", "recovery_agent"]
            else scope.selected_service;
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
