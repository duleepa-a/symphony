"""Ports for feature-owner exports. No fixture is selected by production."""
import from contracts { DashboardState, OperationEnvelope }

obj FeaturePorts {
    has dashboard: Callable[[], DashboardState] | None = None,
        handlers: dict[str, Callable[..., OperationEnvelope]] = {};
}

glob active_ports = FeaturePorts();

def configure_ports(ports: FeaturePorts) -> None {
    active_ports = ports;
}

def get_ports() -> FeaturePorts {
    return active_ports;
}
