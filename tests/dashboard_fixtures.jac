"""Test-only providers. Never imported by the production composition root."""
sv {
    import from contracts { DashboardState, OperationEnvelope, OperationError }
    import from catalog { initial_dashboard_state }
    import from integration.ports { FeaturePorts }
    import time;

    glob fixture_state = initial_dashboard_state(),
         fixture_sequence: int = 0,
         fixture_case: str = "completed";

    def set_fixture_case(case_name: str) {
        fixture_case = case_name;
    }

    def fixture_dashboard -> DashboardState {
        return fixture_state;
    }

    def fixture_start(incident_id: str) -> OperationEnvelope {
        fixture_sequence += 1;
        fixture_state = initial_dashboard_state();
        fixture_state.simulation_run_id = f"fixture-{fixture_sequence}";
        down = ["auth", "payment", "api_gateway", "frontend"]
            if incident_id == "auth_outage"
            else ["payment", "api_gateway", "frontend"]
                if incident_id == "payment_outage"
                else [];
        for service in fixture_state.services {
            service.state = "down" if service.id in down else "healthy";
        }
        return OperationEnvelope(
            status="completed",
            data={
                "incident_id": incident_id,
                "services": fixture_state.services,
                "simulation_run_id": fixture_state.simulation_run_id
            }
        );
    }

    def fixture_reset -> OperationEnvelope {
        return fixture_start("normal");
    }

    def fixture_error -> OperationEnvelope {
        return OperationEnvelope(
            status="failed",
            error=OperationError(
                code="fixture_timeout",
                message="Fixture provider timed out. No live provider was called."
            )
        );
    }

    def fixture_scan(service_id: str) -> OperationEnvelope {
        case_name = fixture_case;
        if case_name == "slow" {
            time.sleep(2);
        }
        if case_name == "failed" {
            return fixture_error();
        }
        if case_name == "not_implemented" {
            return OperationEnvelope(
                status="not_implemented",
                error=OperationError(
                    code="fixture_unavailable",
                    message="Fixture adapter is not connected."
                )
            );
        }
        inventory = [
            item
            for service in fixture_state.services
            if service.id == service_id for item in service.inventory
        ];
        item = inventory[0];
        advisories: list[dict[str, any]] = [];
        if case_name != "empty" {
            advisories.append(
                {
                    "id": "FIXTURE-2026-001",
                    "summary": "Fixture advisory for presentation testing; no external request was made.",
                    "severity": None,
                    "reference_url": "https://osv.dev/"
                }
            );
        }
        partial = case_name == "partial";
        return OperationEnvelope(
            status="partial" if partial else "completed",
            data={
                "service_id": service_id,
                "inventory": inventory,
                "finding_count": len(advisories),
                "packages": [
                    {
                        "name": item.name,
                        "version": item.version,
                        "ecosystem": item.ecosystem,
                        "status": "partial" if partial else "completed",
                        "advisories": advisories,
                        "error": {
                            "message": "Fixture advisory detail lookup failed; coverage is incomplete."
                        }
                            if partial
                            else None
                    }
                ]
            },
            error=OperationError(
                code="fixture_partial",
                message="Fixture partial response; some details are unavailable."
            )
                if partial
                else None
        );
    }

    def fixture_investigation -> OperationEnvelope {
        if fixture_case == "slow" {
            time.sleep(2);
        }
        if fixture_case == "failed" {
            return fixture_error();
        }
        evidence_id = f"trace-{fixture_state.simulation_run_id}";
        return OperationEnvelope(
            status="partial" if fixture_case == "partial" else "completed",
            data={
                "tool_timeline": [
                    "check_service_health(payment)",
                    "trace_requests(payment)"
                ],
                "evidence": [
                    {
                        "id": evidence_id,
                        "tool": "trace_requests",
                        "service_id": "payment",
                        "observation": {
                            "source_id": "payment",
                            "target_id": "auth",
                            "message": "Fixture request timed out."
                        },
                        "simulation_run_id": fixture_state.simulation_run_id
                    }
                ],
                "candidate_root_causes": [
                    "Auth dependency is unavailable (fixture hypothesis)."
                ],
                "discovered_dependencies": []
                    if fixture_case == "empty"
                    else [
                        {
                            "source_id": "payment",
                            "target_id": "auth",
                            "kind": "discovered",
                            "evidence_ids": [evidence_id]
                        }
                    ],
                "explanation": "Fixture conclusion supported by the referenced trace. This is not model-generated output."
            }
        );
    }

    def fixture_impact(service_id: str) -> OperationEnvelope {
        if fixture_case == "failed" {
            return fixture_error();
        }
        return OperationEnvelope(
            status="completed",
            data={
                "dependent_services": []
                    if fixture_case == "empty"
                    else ["API Gateway", "Frontend"],
                "relationships": [
                    {
                        "source_id": "api_gateway",
                        "target_id": service_id,
                        "kind": "documented"
                    }
                ],
                "potential_exposure": "Fixture potential exposure through dependencies; no compromise has been established.",
                "priority": "review"
            }
        );
    }

    def fixture_recovery(service_id: str) -> OperationEnvelope {
        if fixture_case == "failed" {
            return fixture_error();
        }
        return OperationEnvelope(
            status="completed",
            data={
                "candidate_repair": f"Fixture preview: restore {service_id}",
                "before": [
                    {"id": s.id, "state": s.state} for s in fixture_state.services
                ],
                "after": [
                    {"id": s.id, "state": "healthy"} for s in fixture_state.services
                ],
                "outcome": "Fixture verification passed. Active simulation was not mutated."
            }
        );
    }

    def fixture_diagnostic(service_id: str) -> OperationEnvelope {
        return OperationEnvelope(
            status="completed",
            data={
                "id": "fixture-health",
                "tool": "check_service_health",
                "service_id": service_id,
                "observation": {"state": "down"},
                "simulation_run_id": fixture_state.simulation_run_id
            }
        );
    }

    def fixture_ports -> FeaturePorts {
        return FeaturePorts(
            dashboard=fixture_dashboard,
            handlers={
                "start_incident": fixture_start,
                "reset_incident": fixture_reset,
                "run_investigation": fixture_investigation,
                "scan_service_dependencies": fixture_scan,
                "analyze_security_impact": fixture_impact,
                "preview_recovery": fixture_recovery,
                "check_service_health": fixture_diagnostic,
                "get_service_logs": fixture_diagnostic,
                "trace_requests": fixture_diagnostic
            }
        );
    }
}
