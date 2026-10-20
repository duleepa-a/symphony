"""Real HTTP service provider querying standalone Docker microservices.

Fetches /health, /logs, and /traces from local microservices over HTTP and
normalizes responses to the Evidence contracts expected by Symphony.
"""
sv {
    import json;
    import os;
    import time;
    import urllib.request;
    import urllib.error;

    import from topology { topology_services, topology_url }
    import from integration.registry { ensure_registry, registry_status }
    import from contracts {
        DashboardState,
        DashboardSummary,
        Evidence,
        OperationEnvelope,
        Service
    }
    import from integration.service_provider { get_service_mode }
    import from integration.real_store {
        current_real_run_id,
        issue_real_evidence_record,
        observe_real_states
    }
    import from simulation.state {
        is_known_service,
        known_dependencies,
        unknown_service
    }

    glob DEFAULT_SERVICE_PORTS: dict[str, int] = {
             "frontend": 8100,
             "auth": 8101,
             "payment": 8102,
             "catalog": 8103,
             "api_gateway": 8104,
             "database": 8105
         };

    glob HTTP_TIMEOUT_SECONDS = 3.0;

    def get_service_base_url(service_id: str) -> str {
        env_var = f"SERVICE_{service_id.upper()}_URL";
        custom = os.getenv(env_var, "").strip();
        if custom {
            return custom.rstrip("/");
        }
        discovered = topology_url(service_id);
        if discovered {
            return discovered;
        }
        if service_id not in DEFAULT_SERVICE_PORTS {
            # No known address: probes fail and the service reads as down.
            return "";
        }
        return f"http://localhost:{DEFAULT_SERVICE_PORTS[service_id]}";
    }

    def issue_real_evidence(
        tool: str, service_id: str, observation: dict[str, any]
    ) -> OperationEnvelope {
        evidence = issue_real_evidence_record(tool, service_id, observation);
        return OperationEnvelope(
            status="completed",
            data={
                "id": evidence.id,
                "tool": evidence.tool,
                "service_id": evidence.service_id,
                "observation": evidence.observation,
                "simulation_run_id": evidence.simulation_run_id
            }
        );
    }

    def http_get_json(
        url: str, run_id: str, timeout: float = HTTP_TIMEOUT_SECONDS
    ) -> dict[str, any] {
        start_t = time.time();
        req = urllib.request.Request(
            url, headers={"Accept": "application/json", "X-Simulation-Run-Id": run_id}
        );
        try {
            response = urllib.request.urlopen(req, timeout=timeout);
            try {
                status = response.getcode();
                body = response.read();
            } finally {
                response.close();
            }
            elapsed_ms = int((time.time() - start_t) * 1000);
            payload = json.loads(body.decode("utf-8"));
            return {"status": status, "payload": payload, "latency_ms": elapsed_ms};
        } except urllib.error.HTTPError as err {
            elapsed_ms = int((time.time() - start_t) * 1000);
            err_payload: dict[str, any] = {"state": "down"};
            try {
                err_payload = json.loads(err.read().decode("utf-8"));
            } except Exception {
                err_payload = {"error": str(err.reason), "state": "down"};
            }
            return {
                "status": err.code,
                "payload": err_payload,
                "latency_ms": elapsed_ms
            };
        } except Exception as err {
            elapsed_ms = int((time.time() - start_t) * 1000);
            return {
                "status": 503,
                "payload": {"error": str(err), "state": "down"},
                "latency_ms": elapsed_ms
            };
        }
    }

    def probe_health(service_id: str) -> dict[str, any] {
        # Observe a service without recording evidence; used by dashboard polling.
        base_url = get_service_base_url(service_id);
        url = f"{base_url}/health";
        res = http_get_json(url, current_real_run_id());
        status_code = res["status"];
        payload = res["payload"];
        latency_ms = res["latency_ms"];

        down = status_code >= 400 or payload.get("state") == "down";
        degraded = payload.get("state") == "degraded";

        state = "down" if down else ("degraded" if degraded else "healthy");
        error_rate = 100 if down else (25 if degraded else 0);

        return {
            "state": state,
            "http_status": status_code,
            "error_rate_pct": error_rate,
            "latency_ms": None if down else latency_ms,
            "message": payload.get("message", f"{service_id} state is {state}")
        };
    }

    def real_check_health(service_id: str) -> OperationEnvelope {
        if not is_known_service(service_id) {
            return unknown_service(service_id);
        }
        return issue_real_evidence(
            "check_service_health", service_id, probe_health(service_id)
        );
    }

    def real_dashboard -> DashboardState {
        ensure_registry();
        registry = registry_status();
        services: list[Service] = [];
        for service in topology_services() {
            state = probe_health(service.id).get("state", "down");
            services.append(
                Service(
                    id=service.id,
                    name=service.name,
                    state=state,
                    inventory=service.inventory
                )
            );
        }

        healthy = len(
            [
                service
                for service in services
                if service.state == "healthy"
            ]
        );
        degraded = len(
            [
                service
                for service in services
                if service.state == "degraded"
            ]
        );
        failed = len(
            [
                service
                for service in services
                if service.state == "down"
            ]
        );
        dependencies = known_dependencies();
        run_id = observe_real_states(
            {service.id: service.state for service in services}
        );
        return DashboardState(
            services=services,
            dependencies=dependencies,
            summary=DashboardSummary(
                total_services=len(services),
                healthy_services=healthy,
                degraded_services=degraded,
                failed_services=failed,
                discovered_dependencies=len(
                    [
                        link
                        for link in dependencies
                        if link.kind == "discovered"
                    ]
                ),
                vulnerability_findings=0
            ),
            simulation_run_id=run_id,
            service_mode=get_service_mode(),
            topology_source=registry["source"],
            topology_error=registry["error"]
        );
    }

    def real_get_logs(service_id: str) -> OperationEnvelope {
        if not is_known_service(service_id) {
            return unknown_service(service_id);
        }
        base_url = get_service_base_url(service_id);
        url = f"{base_url}/logs";
        run_id = current_real_run_id();
        res = http_get_json(url, run_id);
        status_code = res["status"];
        payload = res["payload"];

        entries: list[dict[str, str]] = [];
        if status_code < 400 and "entries" in payload {
            entries = payload.get("entries", []);
        } else {
            entries = [
                {
                    "level": "ERROR",
                    "message": f"Service request failed with HTTP {status_code}: {payload.get(
                        'error', 'connection refused'
                    )}"
                }
            ];
        }
        return issue_real_evidence(
            "get_service_logs", service_id, {"entries": entries}
        );
    }

    def real_trace_requests(service_id: str) -> OperationEnvelope {
        if not is_known_service(service_id) {
            return unknown_service(service_id);
        }
        base_url = get_service_base_url(service_id);
        url = f"{base_url}/traces";
        run_id = current_real_run_id();
        res = http_get_json(url, run_id);
        status_code = res["status"];
        payload = res["payload"];

        requests_list = payload.get("requests", []) if status_code < 400 else [];
        spans: list[dict[str, str]] = [];

        for req in requests_list {
            target = req.get("target_id", "");
            code = req.get("status_code", 200);
            outcome = "ok"
                if code < 400
                else ("timeout" if code == 504 else "error_503");
            spans.append({"direction": "outgoing", "peer": target, "outcome": outcome});
        }

        observation: dict[str, any] = {"requests": requests_list, "spans": spans};
        return issue_real_evidence("trace_requests", service_id, observation);
    }
}
