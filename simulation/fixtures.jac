"""Static response fixtures matching the frozen operation envelopes.

These never touch live simulation state, so the dashboard can develop against
them without importing the simulator. Run IDs are placeholders ("fixture-run").
"""

glob SERVICE_NAMES: dict[str, str] = {
         "frontend": "Frontend",
         "api_gateway": "API Gateway",
         "payment": "Payment",
         "catalog": "Catalog",
         "auth": "Auth",
         "database": "Database"
     };

glob SERVICE_ORDER: list[str] = [
         "frontend",
         "api_gateway",
         "payment",
         "catalog",
         "auth",
         "database"
     ];

glob DOWN_BY_INCIDENT: dict[str, list[str]] = {
         "normal": [],
         "auth_outage": ["auth", "payment", "api_gateway", "frontend"],
         "payment_outage": ["payment", "api_gateway", "frontend"]
     };

def fixture_services(incident_id: str) -> list[dict[str, str]] {
    down = DOWN_BY_INCIDENT[incident_id];
    return [
        {
            "id": service_id,
            "name": SERVICE_NAMES[service_id],
            "state": "down" if service_id in down else "healthy"
        } for service_id in SERVICE_ORDER
    ];
}

def fixture_start_incident(incident_id: str) -> dict[str, any] {
    # Shape of start_incident(incident_id) when completed.
    return {
        "status": "completed",
        "data": {
            "incident_id": incident_id,
            "services": fixture_services(incident_id),
            "simulation_run_id": "fixture-run"
        },
        "error": None
    };
}

def fixture_reset() -> dict[str, any] {
    return {
        "status": "completed",
        "data": {
            "incident_id": "normal",
            "services": fixture_services("normal"),
            "dependencies": [
                {
                    "source_id": "frontend",
                    "target_id": "api_gateway",
                    "kind": "documented",
                    "evidence_ids": []
                },
                {
                    "source_id": "api_gateway",
                    "target_id": "payment",
                    "kind": "documented",
                    "evidence_ids": []
                },
                {
                    "source_id": "api_gateway",
                    "target_id": "catalog",
                    "kind": "documented",
                    "evidence_ids": []
                },
                {
                    "source_id": "payment",
                    "target_id": "database",
                    "kind": "documented",
                    "evidence_ids": []
                },
                {
                    "source_id": "catalog",
                    "target_id": "database",
                    "kind": "documented",
                    "evidence_ids": []
                }
            ],
            "simulation_run_id": "fixture-run"
        },
        "error": None
    };
}

def fixture_health(service_id: str, incident_id: str) -> dict[str, any] {
    down = service_id in DOWN_BY_INCIDENT[incident_id];
    return {
        "status": "completed",
        "data": {
            "id": f"fixture-run-ev-health-{service_id}",
            "tool": "check_service_health",
            "service_id": service_id,
            "observation": {
                "state": "down" if down else "healthy",
                "http_status": 503 if down else 200,
                "error_rate_pct": 100 if down else 0,
                "latency_ms": None if down else 25
            },
            "simulation_run_id": "fixture-run"
        },
        "error": None
    };
}

def fixture_auth_outage_payment_trace() -> dict[str, any] {
    # The trace that supports discovering Payment -> Auth.
    return {
        "status": "completed",
        "data": {
            "id": "fixture-run-ev-trace-payment",
            "tool": "trace_requests",
            "service_id": "payment",
            "observation": {
                "spans": [
                    {"direction": "outgoing", "peer": "database", "outcome": "ok"},
                    {"direction": "outgoing", "peer": "auth", "outcome": "timeout"},
                    {
                        "direction": "incoming",
                        "peer": "api_gateway",
                        "outcome": "error_503"
                    }
                ]
            },
            "simulation_run_id": "fixture-run"
        },
        "error": None
    };
}

def fixture_unknown_service() -> dict[str, any] {
    return {
        "status": "failed",
        "data": {},
        "error": {"code": "unknown_service", "message": "Unknown service ID 'nope'."}
    };
}
