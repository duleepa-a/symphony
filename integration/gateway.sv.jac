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

    import from integration.simulation_adapter { simulation_lock }
    import from integration.agent_ports { graph_key }
    import from integration.result_store { result_store, result_lock }

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
        snapshot = provider() if provider is not None else initial_dashboard_state();
        with result_lock {
            result_store.sync(snapshot.simulation_run_id);
        }
        return snapshot;
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
                                else "security_analyst_not_connected"
                                    if operation == "run_security_analysis"
                                    else "recovery_agent_not_connected"
                                        if operation == "run_recovery_agent"
                                        else "recovery_not_connected";
            return failure(
                code,
                "This feature is not connected. Its implementation must be integrated before live results are available.",
                "not_implemented"
            );
        }
        try {
            before = read_dashboard().simulation_run_id;
            tracked = operation in [
                "scan_service_dependencies",
                "run_investigation",
                "run_security_analysis",
                "run_recovery_agent"
            ];
            ticket = 0;
            if tracked {
                with result_lock {
                    ticket = result_store.begin(operation, service or "", before);
                }
            }
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
                    ],
                    "run_security_analysis": [
                        "service_id",
                        "findings",
                        "priority",
                        "rule_based_priority",
                        "explanation"
                    ],
                    "run_recovery_agent": [
                        "target_service_id",
                        "action",
                        "cited_evidence_ids",
                        "preview"
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
                if service is not None
                and "service_id" in result.data
                and result.data["service_id"] != service {
                    return failure(
                        "invalid_feature_response",
                        "The response belongs to a different service."
                    );
                }
                if operation == "scan_service_dependencies"
                and result.status == "completed"
                and (
                    not isinstance(result.data.get("packages"), list)
                    or not result.data.get("packages")
                ) {
                    return failure(
                        "invalid_feature_response",
                        "A completed scan must include package coverage."
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
            if tracked {
                with simulation_lock {
                    with result_lock {
                        if result.status in ["completed", "partial"]
                        and operation in [
                            "run_security_analysis",
                            "run_recovery_agent"
                        ] {
                            prerequisite = "scan_service_dependencies"
                                if operation == "run_security_analysis"
                                else "run_investigation";
                            input_service = (service or "")
                                if operation == "run_security_analysis"
                                else "";
                            graph_signature = result.data.pop("_graph_signature", None);
                            if graph_signature is not None
                            and graph_key(
                                read_dashboard().dependencies
                            ) != graph_signature {
                                return failure(
                                    "stale_topology",
                                    "The known graph changed before assessment results could be stored."
                                );
                            }
                            input_revision = result.data.pop("_input_revision", None);
                            graph_revision = result.data.pop("_graph_revision", None);
                            if input_revision is not None
                            and result_store.revision(
                                prerequisite, input_service
                            ) != input_revision {
                                return failure(
                                    "stale_prerequisite",
                                    "A newer input replaced these agent results."
                                );
                            }
                            if graph_revision is not None
                            and result_store.revision(
                                "run_investigation"
                            ) != graph_revision {
                                return failure(
                                    "stale_prerequisite",
                                    "The known graph changed during security analysis."
                                );
                            }
                        }
                        if not result_store.commit(
                            operation, service or "", after, ticket, result
                        ) {
                            return failure(
                                "stale_request",
                                "A newer request replaced these results."
                            );
                        }
                    }
                }
            }
            return result;
        } except Exception {
            return failure(
                "feature_execution_failed",
                "The feature could not complete the request. Retry or inspect the server integration."
            );
        }
    }
}
