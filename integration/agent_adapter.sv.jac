"""Orchestrate new agents over copied facts; validate provenance before commit."""
sv {
    import from copy { deepcopy }
    import from dataclasses { asdict }
    import from contracts { OperationEnvelope, OperationError }
    import from integration.agent_ports { AgentPorts, AgentSession, graph_key }
    import from integration.result_store { result_store, result_lock }
    import from integration.simulation_adapter { simulation_lock }
    import from simulation.state { sim_dashboard_state }
    import from simulation.impact { sim_analyze_impact }

    def agent_failure(code: str, message: str) -> OperationEnvelope {
        return OperationEnvelope(
            status="failed", error=OperationError(code=code, message=message)
        );
    }
    def current(run_id: str) -> bool {
        return sim_dashboard_state().simulation_run_id == run_id;
    }
    def advisory_packages(scan: OperationEnvelope) -> dict[str, list[str]] {
        records: dict[str, list[str]] = {};
        for package in scan.data.get("packages", []) {
            for finding in package.get("advisories", package.get("findings", [])) {
                advisory_id = finding.get("id", finding.get("advisory_id", ""));
                if advisory_id not in records {
                    records[advisory_id] = [];
                }
                records[advisory_id].append(
                    package.get("name", package.get("package", ""))
                );
            }
        }
        return records;
    }
    def security_analysis(service_id: str, ports: AgentPorts) -> OperationEnvelope {
        with simulation_lock {
            snapshot = sim_dashboard_state();
            run_id = snapshot.simulation_run_id;
            with result_lock {
                result_store.sync(run_id);
                scan = result_store.latest("scan_service_dependencies", service_id);
                revision = result_store.revision(
                    "scan_service_dependencies", service_id
                );
                graph_revision = result_store.revision("run_investigation");
            }
            if scan is None {
                return agent_failure(
                    "scan_required",
                    "Scan this service in the current simulation before requesting an assessment."
                );
            }
            impact = sim_analyze_impact(service_id);
            if scan.status not in ["completed", "partial"] {
                return agent_failure(
                    "scan_failed",
                    "The latest scan failed. Retry it; deterministic impact remains available."
                );
            }
            if ports.security is None {
                return agent_failure(
                    "security_analyst_not_connected",
                    "The Security Analyst module has not been handed off. Deterministic impact remains available."
                );
            }
            session = AgentSession(
                simulation_run_id=run_id,
                service_id=service_id,
                facts={
                    "scan_results": deepcopy(scan),
                    "impact": deepcopy(impact),
                    "known_dependencies": [
                        asdict(link) for link in snapshot.dependencies
                    ]
                }
            );
        }
        try {
            result = ports.security(session);
        } except Exception {
            return agent_failure(
                "security_agent_execution_failed",
                "The Security Analyst provider or tool failed. Deterministic impact remains available."
            );
        }
        with simulation_lock {
            with result_lock {
                if not current(run_id) {
                    return agent_failure(
                        "stale_run", "The simulation changed during security analysis."
                    );
                }
                if result_store.revision(
                    "scan_service_dependencies", service_id
                ) != revision
                or result_store.revision("run_investigation") != graph_revision {
                    return agent_failure(
                        "stale_prerequisite",
                        "A newer scan replaced this assessment's input. Run the analyst again."
                    );
                }
            }
            if not isinstance(result, OperationEnvelope) {
                return agent_failure(
                    "invalid_agent_response",
                    "The analyst returned an incompatible response."
                );
            }
            if result.status == "failed" {
                return result;
            }
            if result.status not in ["completed", "partial"] {
                return agent_failure(
                    "invalid_agent_response",
                    "The analyst did not complete a supported assessment."
                );
            }
            data = result.data;
            if data.get("simulation_run_id") != run_id
            or data.get("service_id") != service_id {
                return agent_failure(
                    "stale_agent_result",
                    "The assessment does not match this service and simulation."
                );
            }
            if scan is None {
                return agent_failure("scan_required", "No current scan is available.");
            }
            ids = advisory_packages(scan);
            dependents = impact.data.get("dependent_services", []);
            if data.get("dependents") != dependents {
                return agent_failure(
                    "unsupported_dependents",
                    "The assessment must use the deterministic dependent services."
                );
            }
            findings: list[dict[str, any]] = data.get("findings", []);
            if not isinstance(findings, list) {
                return agent_failure(
                    "invalid_assessment",
                    "The assessment omitted its per-finding results."
                );
            }
            for finding in findings {
                if not isinstance(finding, dict) {
                    return agent_failure(
                        "invalid_assessment",
                        "Each finding must be a structured advisory assessment."
                    );
                }
                cited = finding.get("cited_advisory_ids", []);
                advisory_id = finding.get("advisory_id", "");
                if advisory_id not in ids
                or finding.get("package") not in ids[advisory_id]
                or not isinstance(cited, list)
                or not cited
                or advisory_id not in cited
                or `any(item not in ids for item in cited) {
                    return agent_failure(
                        "unsupported_advisory",
                        "A finding cites an advisory or package outside the current scan."
                    );
                }
            }
            if {
                (advisory_id, package) for advisory_id in ids
                for package in ids[advisory_id]
            } != {
                (item.get("advisory_id"), item.get("package")) for item in findings
            } {
                return agent_failure(
                    "incomplete_assessment",
                    "The assessment must cover every advisory in the current scan."
                );
            }
            explanation = str(data.get("explanation", ""));
            claim = explanation.lower() + " " + " ".join(
                str(item.get("risk", "")).lower() for item in findings
            );
            normalized_claim = claim.replace("_", " ").replace("-", " ");
            dependent_claim = `any(
                dependent.lower().replace("_", " ") in normalized_claim
                for dependent in dependents
            )
            or `any(
                word in normalized_claim
                for word in ["dependent", "downstream", "upstream"]
            );
            if dependent_claim and ("compromised" in claim or "vulnerable" in claim) {
                return agent_failure(
                    "unsupported_security_claim",
                    "Dependency reach does not establish that a dependent is vulnerable or compromised."
                );
            }
            if scan.status == "partial"
            and `any(
                phrase in claim
                for phrase in [
                    "all clear",
                    "all-clear",
                    "no vulnerabilities",
                    "verified clean"
                ]
            ) {
                return agent_failure(
                    "incomplete_scan_claim",
                    "An incomplete scan cannot support an all-clear claim."
                );
            }
            priorities = {"low": 0, "medium": 1, "high": 2};
            priority = data.get("priority", "");
            rule = impact.data.get("priority", "low");
            if priority not in priorities or not explanation {
                return agent_failure(
                    "invalid_assessment",
                    "A priority and evidence-based explanation are required."
                );
            }
            data["rule_based_priority"] = rule;
            data["priority_below_rule_based"] = priorities[priority] < priorities[rule];
            data["scan_status"] = scan.status;
            data["_input_revision"] = revision;
            if graph_key(sim_dashboard_state().dependencies) != graph_key(
                snapshot.dependencies
            ) {
                return agent_failure(
                    "stale_topology",
                    "The known graph changed during security analysis."
                );
            }
            data["_graph_revision"] = graph_revision;
            data["_graph_signature"] = graph_key(snapshot.dependencies);
            if scan.status == "partial" {
                result.status = "partial";
                result.error = OperationError(
                    code="scan_incomplete",
                    message="Scan coverage is incomplete; this assessment is not an all-clear."
                );
            }
            return result;
        }
    }
    def recovery_analysis(ports: AgentPorts) -> OperationEnvelope {
        with simulation_lock {
            snapshot = sim_dashboard_state();
            run_id = snapshot.simulation_run_id;
            with result_lock {
                result_store.sync(run_id);
                investigation = result_store.latest("run_investigation");
                revision = result_store.revision("run_investigation");
            }
            if investigation is None
            or investigation.status != "completed"
            or not investigation.data.get("evidence") {
                return agent_failure(
                    "investigation_required",
                    "Complete an evidence-backed investigation in this simulation before requesting a repair proposal."
                );
            }
            if ports.recovery is None
            or ports.repair_options is None
            or ports.preview is None {
                return agent_failure(
                    "recovery_agent_not_connected",
                    "The Recovery agent and action-preview exports have not been handed off. Manual deterministic preview remains available."
                );
            }
            impacts = {
                service.id: sim_analyze_impact(service.id).data
                for service in snapshot.services
            };
        }
        try {
            options = ports.repair_options();
            if not isinstance(options, list)
            or not options
            or `any(not isinstance(item, str) for item in options) {
                return agent_failure(
                    "repair_options_unavailable",
                    "The simulator must supply supported repair actions."
                );
            }
            session = AgentSession(
                simulation_run_id=run_id,
                facts={
                    "investigation_result": deepcopy(investigation),
                    "impacts": deepcopy(impacts),
                    "repair_options": deepcopy(options)
                }
            );
            result = ports.recovery(session);
        } except Exception {
            return agent_failure(
                "recovery_agent_execution_failed",
                "The Recovery agent provider or tool failed. Manual preview remains available."
            );
        }
        with simulation_lock {
            with result_lock {
                if not current(run_id) {
                    return agent_failure(
                        "stale_run", "The simulation changed during recovery planning."
                    );
                }
                if result_store.revision("run_investigation") != revision {
                    return agent_failure(
                        "stale_prerequisite",
                        "A newer investigation replaced this proposal's evidence."
                    );
                }
            }
            if not isinstance(result, OperationEnvelope) {
                return agent_failure(
                    "invalid_agent_response",
                    "The Recovery agent returned an incompatible response."
                );
            }
            if result.status == "failed" {
                return result;
            }
            if result.status != "completed" {
                return agent_failure(
                    "invalid_agent_response",
                    "The Recovery agent did not complete a proposal."
                );
            }
            data = result.data;
            if data.get("simulation_run_id") != run_id {
                return agent_failure(
                    "stale_agent_result", "The proposal belongs to another simulation."
                );
            }
            target = data.get("target_service_id", "");
            action = data.get("action", "");
            if target not in impacts or action not in options {
                return agent_failure(
                    "unsupported_repair",
                    "The proposal must select a known service and a listed repair action."
                );
            }
            if investigation is None {
                return agent_failure(
                    "investigation_required", "No current investigation is available."
                );
            }
            evidence: list[dict[str, any]] = investigation.data["evidence"];
            evidence_ids = {
                item.get("id")
                for item in evidence
                if item.get("simulation_run_id") == run_id
            };
            cited = data.get("cited_evidence_ids", []);
            if not cited or `any(item not in evidence_ids for item in cited) {
                return agent_failure(
                    "unsupported_repair_evidence",
                    "The proposal must cite evidence from the current investigation."
                );
            }
            if not data.get("rationale") {
                return agent_failure(
                    "invalid_proposal",
                    "The repair proposal requires an evidence-based rationale."
                );
            }
            try {
                preview = ports.preview(target, action);
            } except Exception {
                return agent_failure(
                    "recovery_preview_failed",
                    "The deterministic action preview failed."
                );
            }
            if not current(run_id) {
                return agent_failure(
                    "stale_run", "The simulation changed during recovery verification."
                );
            }
            if not isinstance(preview, OperationEnvelope) {
                return agent_failure(
                    "invalid_recovery_preview",
                    "The simulator returned an incompatible preview."
                );
            }
            if preview.status != "completed" {
                return preview;
            }
            if preview.data.get("outcome") not in [
                "recovered",
                "not_recovered",
                "no_incident"
            ]
            or "before" not in preview.data
            or "after" not in preview.data {
                return agent_failure(
                    "invalid_recovery_preview",
                    "The simulator returned an invalid verification result."
                );
            }
            data["_input_revision"] = revision;
            data["preview"] = {
                "before": deepcopy(preview.data["before"]),
                "after": deepcopy(preview.data["after"]),
                "outcome": preview.data["outcome"]
            };
            return result;
        }
    }
}
