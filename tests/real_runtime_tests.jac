"""Real-service mode keeps its own run identity and a bounded evidence store."""
import os;
import from integration.real_store {
    current_real_run_id,
    issue_real_evidence_record,
    lookup_real_evidence,
    observe_real_states,
    real_runtime,
    reset_real_runtime
}
import from integration.real_provider { real_dashboard }
import from integration.run_context {
    accept_discovered_dependency,
    current_dashboard,
    is_current_run
}
import from simulation.state { sim_state, sim_reset, known_dependencies }

glob ALL_URL_KEYS = [
         "SERVICE_FRONTEND_URL",
         "SERVICE_API_GATEWAY_URL",
         "SERVICE_PAYMENT_URL",
         "SERVICE_CATALOG_URL",
         "SERVICE_AUTH_URL",
         "SERVICE_DATABASE_URL"
     ];

def healthy() -> dict[str, str] {
    return {
        "frontend": "healthy",
        "api_gateway": "healthy",
        "payment": "healthy",
        "catalog": "healthy",
        "auth": "healthy",
        "database": "healthy"
    };
}

def with_real_mode_offline() -> dict[str, str | None] {
    previous: dict[str, str | None] = {};
    for key in ALL_URL_KEYS + ["SYMPHONY_SERVICE_MODE"] {
        previous[key] = os.environ.get(key);
    }
    os.environ["SYMPHONY_SERVICE_MODE"] = "real";
    for key in ALL_URL_KEYS {
        os.environ[key] = "http://127.0.0.1:59999";
    }
    reset_real_runtime();
    return previous;
}

def restore(previous: dict[str, str | None]) {
    for (key, old) in previous.items() {
        if old is not None {
            os.environ[key] = old;
        } else {
            os.environ.pop(key, None);
        }
    }
    reset_real_runtime();
}

test "first observation adopts a baseline without starting a new run" {
    reset_real_runtime();
    first = current_real_run_id();
    assert observe_real_states(healthy()) == first;
    assert observe_real_states(healthy()) == first;
}

test "a service state change rotates the run and clears its evidence" {
    reset_real_runtime();
    observe_real_states(healthy());
    before = current_real_run_id();
    record = issue_real_evidence_record(
        "check_service_health", "auth", {"state": "healthy"}
    );
    assert lookup_real_evidence(record.id) is not None;
    changed = healthy();
    changed["auth"] = "down";
    after = observe_real_states(changed);
    assert after != before;
    assert current_real_run_id() == after;
    assert lookup_real_evidence(record.id) is None;
    assert record.simulation_run_id == before;
}

test "evidence retention is bounded and drops the oldest records first" {
    reset_real_runtime();
    previous = os.environ.get("SYMPHONY_EVIDENCE_LIMIT");
    os.environ["SYMPHONY_EVIDENCE_LIMIT"] = "10";
    try {
        records = [
            issue_real_evidence_record("get_service_logs", "auth", {"n": index})
            for index in range(25)
        ];
        assert len(real_runtime.evidence_log) == 10;
        assert lookup_real_evidence(records[0].id) is None;
        assert lookup_real_evidence(records[14].id) is None;
        assert lookup_real_evidence(records[15].id) is not None;
        assert lookup_real_evidence(records[24].id) is not None;
    } finally {
        if previous is not None {
            os.environ["SYMPHONY_EVIDENCE_LIMIT"] = previous;
        } else {
            os.environ.pop("SYMPHONY_EVIDENCE_LIMIT", None);
        }
        reset_real_runtime();
    }
}

test "an invalid retention setting falls back to a safe bound" {
    reset_real_runtime();
    previous = os.environ.get("SYMPHONY_EVIDENCE_LIMIT");
    os.environ["SYMPHONY_EVIDENCE_LIMIT"] = "not-a-number";
    try {
        for index in range(30) {
            issue_real_evidence_record("get_service_logs", "auth", {"n": index});
        }
        assert len(real_runtime.evidence_log) == 30;
        os.environ["SYMPHONY_EVIDENCE_LIMIT"] = "1";
        issue_real_evidence_record("get_service_logs", "auth", {"n": 99});
        assert len(real_runtime.evidence_log) == 10;
    } finally {
        if previous is not None {
            os.environ["SYMPHONY_EVIDENCE_LIMIT"] = previous;
        } else {
            os.environ.pop("SYMPHONY_EVIDENCE_LIMIT", None);
        }
        reset_real_runtime();
    }
}

test "real dashboard polling uses its own run and records no evidence" {
    previous = with_real_mode_offline();
    simulator_run = sim_state.simulation_run_id;
    try {
        first = real_dashboard();
        second = real_dashboard();
        assert first.simulation_run_id.startswith("real-");
        assert first.simulation_run_id == second.simulation_run_id;
        assert len(real_runtime.evidence_log) == 0;
        assert sim_state.simulation_run_id == simulator_run;
    } finally {
        restore(previous);
    }
}

test "the active run follows the mode, and simulator resets do not affect real runs" {
    previous = with_real_mode_offline();
    try {
        snapshot = current_dashboard();
        real_run = snapshot.simulation_run_id;
        assert is_current_run(real_run);
        assert not is_current_run(sim_state.simulation_run_id);
        sim_reset();
        assert is_current_run(real_run);
        os.environ["SYMPHONY_SERVICE_MODE"] = "mock";
        assert not is_current_run(real_run);
        assert is_current_run(sim_state.simulation_run_id);
    } finally {
        restore(previous);
    }
}

test "real mode accepts a discovered dependency only from current real trace evidence" {
    previous = with_real_mode_offline();
    sim_reset();
    try {
        current_dashboard();
        evidence = issue_real_evidence_record(
            "trace_requests",
            "payment",
            {
                "spans": [
                    {"direction": "outgoing", "peer": "auth", "outcome": "error_503"}
                ]
            }
        );
        unrelated = issue_real_evidence_record(
            "trace_requests",
            "payment",
            {"spans": [{"direction": "outgoing", "peer": "catalog", "outcome": "ok"}]}
        );
        rejected = accept_discovered_dependency("payment", "auth", [unrelated.id]);
        assert rejected.status == "failed";
        missing = accept_discovered_dependency("payment", "auth", ["real-1-ev-999"]);
        assert missing.status == "failed";
        accepted = accept_discovered_dependency("payment", "auth", [evidence.id]);
        assert accepted.status == "completed";
        discovered = [
            link
            for link in known_dependencies()
            if link.kind == "discovered"
        ];
        assert len(discovered) == 1;
    } finally {
        restore(previous);
        sim_reset();
    }
}

test "evidence from an earlier real run cannot support a discovery" {
    previous = with_real_mode_offline();
    sim_reset();
    try {
        current_dashboard();
        observe_real_states(healthy());
        evidence = issue_real_evidence_record(
            "trace_requests",
            "payment",
            {"spans": [{"direction": "outgoing", "peer": "auth", "outcome": "ok"}]}
        );
        changed = healthy();
        changed["database"] = "down";
        observe_real_states(changed);
        result = accept_discovered_dependency("payment", "auth", [evidence.id]);
        assert result.status == "failed";
        assert result.error is not None;
        if result.error is not None {
            assert result.error.code == "unknown_or_stale_evidence";
        }
    } finally {
        restore(previous);
        sim_reset();
    }
}
