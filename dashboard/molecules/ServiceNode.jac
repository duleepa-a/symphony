"""A graph node is keyboard-selectable and never infers missing health as healthy."""
import from ...contracts { Service }

def:pub ServiceNode(
    service: Service, selected: bool, on_select: Callable[[str], None]
) -> JsxElement {
    classes = {
        "frontend": "node-frontend",
        "api_gateway": "node-gateway",
        "payment": "node-payment",
        "catalog": "node-catalog",
        "auth": "node-auth",
        "database": "node-database"
    };
    node_class = classes[service.id] if service.id in classes else "";
    <button
        type="button"
        className={f"service-node {node_class} state-{service.state}"}
        aria-pressed={selected}
        aria-label={f"Select {service.name}, {service.state}"}
        onClick={lambda { on_select(service.id); }}
        data-service-id={service.id}
        data-state={service.state}
    >
        <span className="node-state" aria-hidden="true"></span>
        <span>
            <strong>{service.name}</strong>
            <small>{service.state}</small>
        </span>
    </button>
}
