"""Validate requests and guard feature results at the application boundary."""
sv {
    import from contracts {
        DashboardState,
        OperationEnvelope,
        OperationError,
        Evidence,
        Dependency
    }
    import from catalog { initial_dashboard_state }
    import from integration.ports { get_ports }

    import from integration.evidence { supports_dependency }

    glob SERVICE_IDS = [
             "frontend",
             "api_gateway",
             "payment",
             "catalog",
             "auth",
             "database"
         ];

    def failure(code: str, message: str, status: str = "failed") -> OperationEnvelope {
        return OperationEnvelope(
            status=status, error=OperationError(code=code, message=message)
        );
    }

    def read_dashboard() -> DashboardState {
        provider = get_ports().dashboard;
        return provider() if provider is not None else initial_dashboard_state();
    }

    def field(raw: any, key: str, fallback: any = None) -> any {
        if isinstance(raw, dict) {
            return raw.get(key, fallback);
        }
        return getattr(raw, key, fallback);
    }

    def discovery_is_supported(data: dict[str, any], run_id: str) -> bool {
        evidence = data.get("evidence", []);
        for dependency in data.get("discovered_dependencies", []) {
            ids = field(dependency, "evidence_ids", []);
            source = field(dependency, "source_id", "");
            target = field(dependency, "target_id", "");
            if not ids
            or source not in SERVICE_IDS
            or target not in SERVICE_IDS
            or source == target {
                return False;
            }
            records = [
                Evidence(
                    id=field(item, "id", ""),
                    tool=field(item, "tool", ""),
                    service_id=field(item, "service_id", ""),
                    observation=field(item, "observation", {}),
                    simulation_run_id=field(item, "simulation_run_id", "")
                ) for item in evidence
            ];
            if not supports_dependency(
                Dependency(source_id=source, target_id=target, evidence_ids=ids),
                records,
                run_id
            ) {
                return False;
            }
        }
        return True;
    }

    def invoke(operation: str, arguments: dict[str, any]) -> OperationEnvelope {
        service = arguments.get("service_id");
        if service is not None and service not in SERVICE_IDS {
            return failure(
                "invalid_service", "Select one of the six documented services."
            );
        }
        if operation == "start_incident"
        and arguments.get("incident_id") not in [
            "normal",
            "auth_outage",
            "payment_outage"
        ] {
            return failure("invalid_incident", "Select a supported incident scenario.");
        }
        handler = get_ports().handlers.get(operation);
        if handler is None {
            code = "simulation_not_connected"
                if operation in ["start_incident", "reset_incident"]
                else "diagnostics_not_connected"
                    if operation in [
                        "check_service_health",
                        "get_service_logs",
                        "trace_requests"
                    ]
                    else "osv_not_connected"
                        if operation == "scan_service_dependencies"
                        else "investigator_not_connected"
                            if operation == "run_investigation"
                            else "impact_analysis_not_connected"
                                if operation == "analyze_security_impact"
                                else "recovery_not_connected";
            return failure(
                code,
                "This feature is not connected. Its implementation must be integrated before live results are available.",
                "not_implemented"
            );
        }
        try {
            before = read_dashboard().simulation_run_id;
            result = handler(**arguments);
            after = read_dashboard().simulation_run_id;
            if not isinstance(result, OperationEnvelope) {
                return failure(
                    "invalid_feature_response",
                    "The feature returned an incompatible response."
                );
            }
            if result.status not in [
                "completed",
                "running",
                "partial",
                "failed",
                "not_implemented",
                "simulation_not_connected"
            ] {
                return failure(
                    "invalid_feature_response",
                    "The feature returned an unsupported completion status."
                );
            }
            if operation not in ["start_incident", "reset_incident"]
            and before != after {
                return failure(
                    "stale_run",
                    "The simulation changed during this request. Run the operation again."
                );
            }
            response_run = result.data.get("simulation_run_id", after);
            if response_run != after {
                return failure(
                    "stale_run",
                    "Results belong to an earlier simulation and were discarded."
                );
            }
            if result.status in ["completed", "partial"] {
                required = {
                    "start_incident": ["services", "simulation_run_id"],
                    "reset_incident": ["services", "simulation_run_id"],
                    "scan_service_dependencies": [
                        "service_id",
                        "inventory",
                        "packages",
                        "finding_count"
                    ],
                    "run_investigation": ["discovered_dependencies", "explanation"],
                    "analyze_security_impact": [
                        "dependent_services",
                        "relationships",
                        "potential_exposure",
                        "priority"
                    ],
                    "preview_recovery": [
                        "candidate_repair",
                        "before",
                        "after",
                        "outcome"
                    ]
                };
                if `any(
                    key not in result.data for key in required.get(operation, [])
                ) {
                    return failure(
                        "invalid_feature_response",
                        "The feature omitted required result fields."
                    );
                }
                if operation == "run_investigation"
                and `any(
                    field(item, "simulation_run_id", "") != after
                    for item in result.data.get("evidence", [])
                ) {
                    return failure(
                        "stale_run",
                        "Diagnostic evidence belongs to an earlier simulation and was discarded."
                    );
                }
                if operation == "run_investigation"
                and not discovery_is_supported(result.data, after) {
                    return failure(
                        "unsupported_discovery",
                        "A proposed relationship has no matching trace evidence for this simulation."
                    );
                }
            }
            result.data = {** result.data, "simulation_run_id": after};
            return result;
        } except Exception {
            return failure(
                "feature_execution_failed",
                "The feature could not complete the request. Retry or inspect the server integration."
            );
        }
    }
}
