"""Deterministic demonstration inventory and documented topology."""

import from contracts {
    PackageInventoryItem,
    Service,
    Dependency,
    DashboardSummary,
    DashboardState
}

def initial_services -> list[Service] {
    return [
        Service(
            id="frontend",
            name="Frontend",
            inventory=[
                PackageInventoryItem(name="react", ecosystem="npm", version="18.2.0")
            ]
        ),
        Service(
            id="api_gateway",
            name="API Gateway",
            inventory=[
                PackageInventoryItem(name="fastapi", ecosystem="PyPI", version="0.95.0")
            ]
        ),
        Service(
            id="payment",
            name="Payment",
            inventory=[
                PackageInventoryItem(name="jinja2", ecosystem="PyPI", version="2.4.1")
            ]
        ),
        Service(
            id="catalog",
            name="Catalog",
            inventory=[
                PackageInventoryItem(name="lodash", ecosystem="npm", version="4.17.20")
            ]
        ),
        Service(
            id="auth",
            name="Auth",
            inventory=[
                PackageInventoryItem(name="pyjwt", ecosystem="PyPI", version="1.7.1")
            ]
        ),
        Service(
            id="database",
            name="Database",
            inventory=[
                PackageInventoryItem(name="pg", ecosystem="npm", version="8.11.3")
            ]
        )
    ];
}

def documented_dependencies -> list[Dependency] {
    return [
        Dependency(source_id="frontend", target_id="api_gateway"),
        Dependency(source_id="api_gateway", target_id="payment"),
        Dependency(source_id="api_gateway", target_id="catalog"),
        Dependency(source_id="payment", target_id="database"),
        Dependency(source_id="catalog", target_id="database")
    ];
}

def initial_dashboard_state -> DashboardState {
    return DashboardState(
        services=initial_services(),
        dependencies=documented_dependencies(),
        summary=DashboardSummary(total_services=6, healthy_services=6),
        simulation_run_id="initial"
    );
}
