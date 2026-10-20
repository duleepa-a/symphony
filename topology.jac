"""Active service topology.

Defaults to the six-service demonstration catalog. Real mode replaces it at
runtime with services found by the registry. The simulator keeps using the
fixed catalog directly.
"""
import from copy { deepcopy }
import from threading { RLock }
import from contracts { Dependency, Service }
import from catalog { documented_dependencies, initial_services }

obj Topology {
    has services: list[Service] | None = None,
        dependencies: list[Dependency] | None = None,
        urls: dict[str, str] = {},
        source: str = "catalog";
}

glob active_topology: Topology = Topology(),
     topology_lock = RLock();

def topology_services -> list[Service] {
    with topology_lock {
        if active_topology.services is None {
            return initial_services();
        }
        return deepcopy(active_topology.services);
    }
}

def topology_dependencies -> list[Dependency] {
    with topology_lock {
        if active_topology.dependencies is None {
            return documented_dependencies();
        }
        return deepcopy(active_topology.dependencies);
    }
}

def topology_ids -> list[str] {
    return [service.id for service in topology_services()];
}

def topology_has(service_id: str) -> bool {
    return service_id in topology_ids();
}

def topology_url(service_id: str) -> str {
    with topology_lock {
        return active_topology.urls.get(service_id, "");
    }
}

def topology_source -> str {
    with topology_lock {
        return active_topology.source;
    }
}

def set_topology(
    services: list[Service],
    dependencies: list[Dependency],
    urls: dict[str, str],
    source: str
) {
    with topology_lock {
        active_topology.services = deepcopy(services);
        active_topology.dependencies = deepcopy(dependencies);
        active_topology.urls = dict(urls);
        active_topology.source = source;
    }
}

def reset_topology {
    with topology_lock {
        active_topology.services = None;
        active_topology.dependencies = None;
        active_topology.urls = {};
        active_topology.source = "catalog";
    }
}
