"""A graph node is keyboard-selectable and never infers missing health as healthy."""
import from ...contracts { Service }
import from ..models.view_models { NodePosition }

def:pub ServiceNode(
    service: Service,
    selected: bool,
    on_select: Callable[[str], None],
    position: NodePosition,
    dim: bool,
    on_hover: Callable[[str], None]
) -> JsxElement {
    return
        <button
            type="button"
            className={f"service-node state-{service.state}{' is-dim' if dim else ''}"}
            style={{
                "--x": f"{position.x_pct}%",
                "--y": f"{position.y_pct}%",
                "--m": f"{position.mobile_pct}%"
            }}
            aria-pressed={selected}
            aria-label={f"Select {service.name}, {service.state}"}
            onClick={lambda { on_select(service.id); }}
            onMouseEnter={lambda { on_hover(service.id); }}
            onMouseLeave={lambda { on_hover(""); }}
            onFocus={lambda { on_hover(service.id); }}
            onBlur={lambda { on_hover(""); }}
            data-service-id={service.id}
            data-state={service.state}
        >
            <span className="node-state" aria-hidden="true"></span>
            <span>
                <strong>{service.name}</strong>
                <small>{service.state}</small>
            </span>
        </button>;
}
