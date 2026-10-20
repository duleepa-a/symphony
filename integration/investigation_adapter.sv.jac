"""Run the Investigator on real diagnostics and atomically accept supported discoveries."""
sv {
    import json;
    import from threading { RLock }
    import from dataclasses { asdict }
    import from contracts { Evidence, OperationEnvelope, OperationError }
    import from catalog { documented_dependencies }
    import from integration.run_context {
        accept_discovered_dependency,
        current_dashboard,
        is_current_run
    }
    import from simulation.diagnostics {
        sim_check_health,
        sim_get_logs,
        sim_trace_requests
    }
    import from investigation.agent { run_investigation_impl }
    import from investigation.tools {
        configure_diagnostic_tools,
        investigation_evidence
    }
    import from integration.simulation_adapter { simulation_lock }
    import from integration.service_provider { is_real_mode }
    import from integration.real_provider {
        real_check_health,
        real_get_logs,
        real_trace_requests
    }
    import from integration.gateway { discovery_is_supported }
    glob investigation_lock = RLock();

    def failure(code: str, message: str) -> OperationEnvelope {
        return OperationEnvelope(
            status="failed", error=OperationError(code=code, message=message)
        );
    }
    def investigate_with(
        runner: Callable[[str, str], OperationEnvelope]
    ) -> OperationEnvelope {
        # Member 2 records tool calls in process-local lists. Serialize sessions,
        # while reset and other short simulator operations remain available.
        with investigation_lock {
            with simulation_lock {
                snapshot = current_dashboard();
                run_id = snapshot.simulation_run_id;
                context = json.dumps(
                    {
                        "services": [asdict(service) for service in snapshot.services],
                        "documented_dependencies": [
                            asdict(link) for link in documented_dependencies()
                        ]
                    }
                );
            }
            def diagnostic(
                handler: Callable[[str], OperationEnvelope], service_id: str
            ) -> Evidence {
                with simulation_lock {
                    if not is_current_run(run_id) {
                        raise RuntimeError("Simulation changed during investigation.");
                    }
                    result = handler(service_id);
                    if result.status != "completed" {
                        raise RuntimeError("Diagnostic service unavailable.");
                    }
                    data = result.data;
                    return Evidence(
                        id=data["id"],
                        tool=data["tool"],
                        service_id=data["service_id"],
                        observation=data["observation"],
                        simulation_run_id=data["simulation_run_id"]
                    );
                }
            }
            def health(service_id: str) -> Evidence {
                handler = real_check_health if is_real_mode() else sim_check_health;
                return diagnostic(handler, service_id);
            }
            def logs(service_id: str) -> Evidence {
                handler = real_get_logs if is_real_mode() else sim_get_logs;
                return diagnostic(handler, service_id);
            }
            def traces(service_id: str) -> Evidence {
                handler = real_trace_requests if is_real_mode() else sim_trace_requests;
                return diagnostic(handler, service_id);
            }
            configure_diagnostic_tools(health, logs, traces);
            result = runner(context, run_id);
            with simulation_lock {
                if not is_current_run(run_id) {
                    return failure(
                        "stale_run",
                        "The simulation changed during investigation. Run it again."
                    );
                }
                result.data["simulation_run_id"] = run_id;
                result.data["evidence"] = [
                    asdict(item) for item in investigation_evidence()
                ];
                if result.status != "completed" {
                    return result;
                }
                if not discovery_is_supported(result.data, run_id) {
                    return failure(
                        "unsupported_discovery",
                        "A proposed relationship lacks matching current-run trace evidence."
                    );
                }
                known = {
                    (link.source_id, link.target_id)
                    for link in current_dashboard().dependencies
                };
                for link in result.data.get("discovered_dependencies", []) {
                    link["kind"] = "discovered";
                    pair = (link["source_id"], link["target_id"]);
                    if pair in known {
                        continue;
                    }
                    accepted = accept_discovered_dependency(
                        link["source_id"], link["target_id"], link["evidence_ids"]
                    );
                    if accepted.status != "completed" {
                        return accepted;
                    }
                    known.add(pair);
                }
                return result;
            }
        }
    }
    def investigate -> OperationEnvelope {
        return investigate_with(run_investigation_impl);
    }
}
