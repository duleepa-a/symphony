"""The service registry decides which services exist; nothing else hard-codes them."""
import os;
import json;
import tempfile;
import from integration.registry {
    apply_topology,
    build_topology,
    parse_host_port,
    parse_packages,
    refresh_registry,
    registry_status,
    reset_registry
}
import from integration.real_provider { real_dashboard, get_service_base_url }
import from integration.real_store { reset_real_runtime }
import from integration.ports { configure_ports }
import from integration.bindings { production_ports }
import from integration.gateway { invoke }
import from security.osv { scan_service_dependencies_impl }
import from topology { topology_ids, topology_dependencies, topology_source }
import from contracts { PackageInventoryItem }

def write_services_file(document: dict[str, any]) -> str {
    handle = tempfile.NamedTemporaryFile(
        mode="w", suffix=".json", delete=False, encoding="utf-8"
    );
    json.dump(document, handle);
    handle.close();
    return handle.name;
}

def use_file_discovery(path: str) -> dict[str, str | None] {
    keys = [
        "SYMPHONY_SERVICE_MODE",
        "SYMPHONY_DISCOVERY",
        "SYMPHONY_SERVICES_FILE",
        "SERVICE_ORDERS_URL"
    ];
    previous: dict[str, str | None] = {};
    for key in keys {
        previous[key] = os.environ.get(key);
    }
    os.environ["SYMPHONY_SERVICE_MODE"] = "real";
    os.environ["SYMPHONY_DISCOVERY"] = "file";
    os.environ["SYMPHONY_SERVICES_FILE"] = path;
    reset_registry();
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
    reset_registry();
    reset_real_runtime();
    configure_ports(production_ports());
}

glob SHOP = {
         "services": [
             {
                 "id": "web",
                 "name": "Storefront",
                 "url": "http://127.0.0.1:59999",
                 "depends_on": ["orders"],
                 "packages": [
                     {"name": "react", "ecosystem": "npm", "version": "18.2.0"}
                 ]
             },
             {
                 "id": "orders",
                 "url": "http://127.0.0.1:59998",
                 "depends_on": ["ledger"]
             },
             {"id": "ledger", "url": "http://127.0.0.1:59997"}
         ]
     };

test "the default topology is the six-service demonstration catalog" {
    assert len(topology_ids()) == 6;
    assert topology_source() == "catalog";
    assert len(topology_dependencies()) == 5;
}

test "package labels support scoped npm names and skip malformed entries" {
    found = parse_packages(
        "PyPI:pyjwt@1.7.1, npm:@scope/pkg@2.0.0, broken, :x@1, npm:y@"
    );
    assert len(found) == 2;
    assert found[0] == {"ecosystem": "PyPI", "name": "pyjwt", "version": "1.7.1"};
    assert found[1] == {"ecosystem": "npm", "name": "@scope/pkg", "version": "2.0.0"};
}

test "docker port mappings resolve to the published host port" {
    ports = "0.0.0.0:8101->8000/tcp, :::8101->8000/tcp, 0.0.0.0:9000->9000/tcp";
    assert parse_host_port(ports, "8000") == "8101";
    assert parse_host_port(ports, "9000") == "9000";
    assert parse_host_port(ports, "7000") == "";
    assert parse_host_port("8000/tcp", "") == "";
    assert parse_host_port("", "8000") == "";
}

test "topology building normalizes IDs and reports every problem" {
    built = build_topology(
        [
            {
                "id": "API-Gateway",
                "depends_on": ["Orders", "orders", "api_gateway", "ghost"]
            },
            {"id": "orders"},
            {"id": "orders"},
            {"id": "9bad"},
            {"id": ""}
        ]
    );
    ids = [service.id for service in built["services"]];
    assert ids == ["api_gateway", "orders"];
    assert built["services"][0].name == "Api Gateway";
    assert len(built["dependencies"]) == 1;
    assert built["dependencies"][0].source_id == "api_gateway";
    assert built["dependencies"][0].target_id == "orders";
    assert len(built["problems"]) == 5;
}

test "file discovery replaces the demo services in real mode" {
    path = write_services_file(SHOP);
    previous = use_file_discovery(path);
    try {
        state = real_dashboard();
        assert [service.id for service in state.services] == [
            "web",
            "orders",
            "ledger"
        ];
        assert state.services[0].name == "Storefront";
        assert state.services[1].name == "Orders";
        assert len(state.services[0].inventory) == 1;
        assert len(state.dependencies) == 2;
        assert state.topology_source == "file";
        assert state.topology_error == "";
        assert state.summary.total_services == 3;
        assert state.summary.failed_services == 3;
        assert get_service_base_url("orders") == "http://127.0.0.1:59998";
    } finally {
        restore(previous);
        os.remove(path);
    }
    assert len(topology_ids()) == 6;
}

test "environment URL overrides still win over discovered addresses" {
    path = write_services_file(SHOP);
    previous = use_file_discovery(path);
    os.environ["SERVICE_ORDERS_URL"] = "http://override.example:1234/";
    try {
        refresh_registry();
        assert get_service_base_url("orders") == "http://override.example:1234";
    } finally {
        restore(previous);
        os.remove(path);
    }
}

test "a failed refresh keeps the last good topology and reports the error" {
    path = write_services_file(SHOP);
    previous = use_file_discovery(path);
    try {
        refresh_registry();
        assert registry_status()["services"] == 3;
        os.environ["SYMPHONY_SERVICES_FILE"] = path + ".missing";
        status = refresh_registry();
        assert "discovery failed" in str(status["error"]);
        assert topology_ids() == ["web", "orders", "ledger"];
        state = real_dashboard();
        assert "discovery failed" in state.topology_error;
    } finally {
        restore(previous);
        os.remove(path);
    }
}

test "failed discovery never falls back to the demo catalog" {
    previous = use_file_discovery("does-not-exist.json");
    try {
        status = refresh_registry();
        assert status["error"] != "";
        assert topology_ids() == [];
        state = real_dashboard();
        assert len(state.services) == 0;
        assert state.topology_error != "";
    } finally {
        restore(previous);
    }
}

test "a file without a services list is rejected" {
    path = write_services_file({"nodes": []});
    previous = use_file_discovery(path);
    try {
        status = refresh_registry();
        assert "services" in str(status["error"]);
        assert topology_ids() == [];
    } finally {
        restore(previous);
        os.remove(path);
    }
}

test "the gateway accepts discovered services and rejects the old catalog IDs" {
    path = write_services_file(SHOP);
    previous = use_file_discovery(path);
    try {
        refresh_registry();
        configure_ports(production_ports());
        accepted = invoke("check_service_health", {"service_id": "orders"});
        assert accepted.status == "completed";
        assert accepted.data["service_id"] == "orders";
        rejected = invoke("check_service_health", {"service_id": "payment"});
        assert rejected.status == "failed";
        assert rejected.error is not None;
        if rejected.error is not None {
            assert rejected.error.code == "invalid_service";
        }
    } finally {
        restore(previous);
        os.remove(path);
    }
}

test "discovered records from any source go through the same validation" {
    previous = use_file_discovery("unused.json");
    try {
        built = apply_topology(
            [
                {"id": "compose-db", "url": "http://localhost:5432", "packages": []},
                {"id": "compose-app", "depends_on": ["compose-db"]}
            ],
            "docker"
        );
        assert topology_ids() == ["compose_db", "compose_app"];
        assert topology_source() == "docker";
        assert len(built["problems"]) == 0;
        assert len(topology_dependencies()) == 1;
    } finally {
        restore(previous);
    }
}

test "a service with no known packages is reported as unscanned, not clean" {
    previous = use_file_discovery("unused.json");
    try {
        apply_topology([{"id": "ledger"}], "file");
        result = scan_service_dependencies_impl("ledger");
        assert result.status == "failed";
        assert result.error is not None;
        if result.error is not None {
            assert result.error.code == "inventory_unavailable";
        }
        unknown = scan_service_dependencies_impl("payment");
        assert unknown.status == "failed";
        if unknown.error is not None {
            assert unknown.error.code == "unknown_service";
        }
    } finally {
        restore(previous);
    }
}
