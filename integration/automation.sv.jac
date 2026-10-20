"""Deduplicated full-assessment orchestration for UI, polling, and webhooks."""
sv {
    import os;
    import from copy { deepcopy }
    import from threading { RLock }
    import from contracts { DashboardState, OperationEnvelope, OperationError }
    import from integration.gateway { read_dashboard, invoke }
    import from topology { topology_ids }

    glob assessment_lock = RLock(),
         assessment_sequence: int = 0,
         last_automatic_signature: str = "",
         latest_assessment: OperationEnvelope | None = None;

    def pack(result: OperationEnvelope) -> dict[str, any] {
        return {
            "status": result.status,
            "data": deepcopy(result.data),
            "error": {"code": result.error.code, "message": result.error.message}
                if result.error
                else None
        };
    }

    def service_signature(snapshot: DashboardState) -> str {
        return "|".join(
            [f"{service.id}:{service.state}" for service in snapshot.services]
        );
    }

    def primary_service(snapshot: DashboardState, requested: str) -> str {
        if requested {
            return requested;
        }
        unhealthy = [
            service.id
            for service in snapshot.services
            if service.state in ["down", "degraded"]
        ];
        return unhealthy[-1] if unhealthy else "";
    }

    def high_finding_count(scan: OperationEnvelope) -> int {
        count = 0;
        for package in scan.data.get("packages", []) {
            for advisory in package.get("advisories", package.get("findings", [])) {
                severity = str(advisory.get("severity", "unknown")).lower();
                if "high" in severity or "critical" in severity {
                    count += 1;
                }
            }
        }
        return count;
    }

    def run_full_assessment_impl(
        trigger: str = "manual", service_id: str = "", force: bool = False
    ) -> OperationEnvelope {
        with assessment_lock {
            if service_id and service_id not in topology_ids() {
                return OperationEnvelope(
                    status="failed",
                    error=OperationError(
                        code="invalid_service",
                        message="Select one of the known services."
                    )
                );
            }
            snapshot = read_dashboard();
            signature = snapshot.simulation_run_id + "|" + service_signature(snapshot);
            target = primary_service(snapshot, service_id);
            automatic_signature = signature + "|" + target;
            automatic = trigger != "manual";
            if automatic
            and not force
            and automatic_signature == last_automatic_signature
            and latest_assessment is not None {
                cached = deepcopy(latest_assessment);
                cached.data = {** cached.data, "deduplicated": True};
                return cached;
            }
            if not target {
                if automatic {
                    last_automatic_signature = automatic_signature;
                }
                return OperationEnvelope(
                    status="completed",
                    data={
                        "assessment_id": "",
                        "trigger": trigger,
                        "skipped": True,
                        "reason": "No failed or degraded service requires assessment.",
                        "simulation_run_id": snapshot.simulation_run_id
                    }
                );
            }
            investigation = invoke("run_investigation", {});
            service_assessments: list[dict[str, any]] = [];
            statuses = [investigation.status];
            scan = OperationEnvelope(status="failed");
            impact = OperationEnvelope(status="failed");
            security = OperationEnvelope(status="failed");
            for service in snapshot.services {
                service_scan = invoke(
                    "scan_service_dependencies", {"service_id": service.id}
                );
                service_impact = invoke(
                    "analyze_security_impact", {"service_id": service.id}
                );
                service_security = invoke(
                    "run_security_analysis", {"service_id": service.id}
                )
                    if service_scan.status in ["completed", "partial"]
                    else OperationEnvelope(
                        status="failed",
                        error=OperationError(
                            code="scan_required",
                            message="Security analysis was skipped because dependency scanning did not complete."
                        )
                    );
                service_assessments.append(
                    {
                        "service_id": service.id,
                        "service_name": service.name,
                        "scan": pack(service_scan),
                        "impact": pack(service_impact),
                        "security_analysis": pack(service_security),
                        "finding_count": service_scan.data.get("finding_count", 0),
                        "high_finding_count": high_finding_count(service_scan),
                        "analyst_priority": service_security.data.get(
                            "priority", "unknown"
                        )
                    }
                );
                statuses.extend(
                    [
                        service_scan.status,
                        service_impact.status,
                        service_security.status
                    ]
                );
                if service.id == target {
                    scan = service_scan;
                    impact = service_impact;
                    security = service_security;
                }
            }
            recovery = invoke("preview_recovery", {"service_id": target});
            proposal = invoke("run_recovery_agent", {})
                if investigation.status in ["completed", "partial"]
                else OperationEnvelope(
                    status="failed",
                    error=OperationError(
                        code="investigation_required",
                        message="Recovery proposal was skipped because investigation did not complete."
                    )
                );
            assessment_sequence += 1;
            statuses.extend([recovery.status, proposal.status]);
            overall = "completed"
                if all(status == "completed" for status in statuses)
                else "partial";
            result = OperationEnvelope(
                status=overall,
                data={
                    "assessment_id": f"assessment-{assessment_sequence}",
                    "trigger": trigger,
                    "primary_service_id": target,
                    "health_signature": signature,
                    "investigation": pack(investigation),
                    "scan": pack(scan),
                    "impact": pack(impact),
                    "security_analysis": pack(security),
                    "service_assessments": service_assessments,
                    "recovery": pack(recovery),
                    "recovery_agent": pack(proposal),
                    "simulation_run_id": snapshot.simulation_run_id,
                    "deduplicated": False,
                    "skipped": False
                }
            );
            latest_assessment = deepcopy(result);
            last_automatic_signature = automatic_signature;
            return result;
        }
    }

    def latest_full_assessment_impl -> OperationEnvelope {
        with assessment_lock {
            if latest_assessment is None {
                return OperationEnvelope(
                    status="not_implemented",
                    error=OperationError(
                        code="assessment_not_available",
                        message="No automated assessment has completed yet."
                    )
                );
            }
            current_run = read_dashboard().simulation_run_id;
            if latest_assessment.data.get("simulation_run_id") != current_run {
                return OperationEnvelope(
                    status="not_implemented",
                    error=OperationError(
                        code="assessment_not_available",
                        message="No automated assessment exists for the current run."
                    )
                );
            }
            return deepcopy(latest_assessment);
        }
    }

    def monitoring_alert_impl(
        service_id: str, state: str, token: str = ""
    ) -> OperationEnvelope {
        expected = os.environ.get("SYMPHONY_WEBHOOK_TOKEN", "");
        if expected and token != expected {
            return OperationEnvelope(
                status="failed",
                error=OperationError(
                    code="invalid_webhook_token",
                    message="The monitoring alert token is invalid."
                )
            );
        }
        if service_id not in topology_ids() {
            return OperationEnvelope(
                status="failed",
                error=OperationError(
                    code="invalid_service", message="Select one of the known services."
                )
            );
        }
        if state not in ["down", "degraded"] {
            return OperationEnvelope(
                status="completed",
                data={
                    "skipped": True,
                    "reason": "Only down or degraded alerts start a full assessment.",
                    "service_id": service_id,
                    "state": state
                }
            );
        }
        return run_full_assessment_impl("webhook", service_id);
    }
}
