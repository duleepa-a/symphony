"""Unit and integration tests for service provider mode switch and real HTTP provider."""
import os;
import from contracts { OperationEnvelope }
import from integration.service_provider {
    get_service_mode,
    is_real_mode,
    MODE_MOCK,
    MODE_REAL,
    MODE_DOCKER
}
import from integration.real_provider {
    get_service_base_url,
    real_check_health,
    real_dashboard,
    real_get_logs,
    real_trace_requests
}
import from integration.ports { configure_ports }
import from integration.bindings { production_ports }
import from integration.gateway { invoke }

test "service provider default mode is mock" {
    original = os.environ.get("SYMPHONY_SERVICE_MODE");
    os.environ.pop("SYMPHONY_SERVICE_MODE", None);
    try {
        assert get_service_mode() == MODE_MOCK;
        assert not is_real_mode();
    } finally {
        if original is not None {
            os.environ["SYMPHONY_SERVICE_MODE"] = original;
        }
    }
}

test "service provider recognizes real and docker modes" {
    original = os.environ.get("SYMPHONY_SERVICE_MODE");
    try {
        os.environ["SYMPHONY_SERVICE_MODE"] = "real";
        assert get_service_mode() == "real";
        assert is_real_mode();

        os.environ["SYMPHONY_SERVICE_MODE"] = "docker";
        assert get_service_mode() == "docker";
        assert is_real_mode();

        os.environ["SYMPHONY_SERVICE_MODE"] = "mock";
        assert not is_real_mode();
    } finally {
        if original is not None {
            os.environ["SYMPHONY_SERVICE_MODE"] = original;
        } else {
            os.environ.pop("SYMPHONY_SERVICE_MODE", None);
        }
    }
}

test "real provider computes correct default ports and respects URL overrides" {
    assert get_service_base_url("frontend") == "http://localhost:8100";
    assert get_service_base_url("auth") == "http://localhost:8101";
    assert get_service_base_url("payment") == "http://localhost:8102";
    assert get_service_base_url("catalog") == "http://localhost:8103";
    assert get_service_base_url("api_gateway") == "http://localhost:8104";
    assert get_service_base_url("database") == "http://localhost:8105";

    os.environ["SERVICE_AUTH_URL"] = "http://auth-container:9999/";
    try {
        assert get_service_base_url("auth") == "http://auth-container:9999";
    } finally {
        os.environ.pop("SERVICE_AUTH_URL", None);
    }
}

test "real provider rejects unknown service IDs" {
    res_health = real_check_health("nonexistent_service");
    assert res_health.status == "failed";
    assert res_health.error is not None;
    if res_health.error is not None {
        assert res_health.error.code == "unknown_service";
    }

    res_logs = real_get_logs("nonexistent_service");
    assert res_logs.status == "failed";
    assert res_logs.error is not None;
    if res_logs.error is not None {
        assert res_logs.error.code == "unknown_service";
    }

    res_traces = real_trace_requests("nonexistent_service");
    assert res_traces.status == "failed";
    assert res_traces.error is not None;
    if res_traces.error is not None {
        assert res_traces.error.code == "unknown_service";
    }
}

test "real provider gracefully reports offline service as down" {
    # Port 59999 is unlikely to be listening; tests offline resilience
    os.environ["SERVICE_DATABASE_URL"] = "http://127.0.0.1:59999";
    try {
        res = real_check_health("database");
        assert res.status == "completed";
        obs = res.data.get("observation", {});
        assert obs.get("state") == "down";
        assert obs.get("http_status") == 503;
        assert obs.get("error_rate_pct") == 100;

        logs_res = real_get_logs("database");
        assert logs_res.status == "completed";
        logs_obs = logs_res.data.get("observation", {});
        entries = logs_obs.get("entries", []);
        assert len(entries) > 0;

        traces_res = real_trace_requests("database");
        assert traces_res.status == "completed";
        traces_obs = traces_res.data.get("observation", {});
        assert traces_obs.get("requests") == [];
    } finally {
        os.environ.pop("SERVICE_DATABASE_URL", None);
    }
}

test "real dashboard reflects offline services instead of static healthy state" {
    original = os.environ.get("SYMPHONY_SERVICE_MODE");
    os.environ["SYMPHONY_SERVICE_MODE"] = "real";
    os.environ["SERVICE_FRONTEND_URL"] = "http://127.0.0.1:59999";
    try {
        state = real_dashboard();
        frontend = [service for service in state.services if service.id == "frontend"][0];
        assert frontend.state == "down";
        assert state.summary.failed_services >= 1;
        assert len(state.dependencies) == 5;
    } finally {
        os.environ.pop("SERVICE_FRONTEND_URL", None);
        if original is not None {
            os.environ["SYMPHONY_SERVICE_MODE"] = original;
        } else {
            os.environ.pop("SYMPHONY_SERVICE_MODE", None);
        }
    }
}

test "bindings switch correctly dispatches operations in mock mode" {
    original = os.environ.get("SYMPHONY_SERVICE_MODE");
    os.environ["SYMPHONY_SERVICE_MODE"] = "mock";
    try {
        configure_ports(production_ports());
        res = invoke("check_service_health", {"service_id": "auth"});
        assert res.status == "completed";
        assert res.data.get("service_id") == "auth";
        obs = res.data.get("observation", {});
        assert obs.get("state") is not None;
    } finally {
        if original is not None {
            os.environ["SYMPHONY_SERVICE_MODE"] = original;
        } else {
            os.environ.pop("SYMPHONY_SERVICE_MODE", None);
        }
    }
}
