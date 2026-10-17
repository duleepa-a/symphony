"""Graph presentation consumes public dependencies, never the simulator's true graph."""
import type from ...contracts { Dependency }
import from ..models.view_models { DependencyView }
import from ...contracts { Service }
import from ..molecules.ServiceNode { ServiceNode }
import from ..molecules.GraphEdge { GraphEdge }

def related_ids(
    service_id: str, dependencies: list[Dependency | DependencyView]
) -> list[str] {
    ids: list[str] = [];
    for dependency in dependencies {
        if dependency.source_id == service_id and dependency.target_id not in ids {
            ids.append(dependency.target_id);
        }
        if dependency.target_id == service_id and dependency.source_id not in ids {
            ids.append(dependency.source_id);
        }
    }
    return ids;
}

def depends_on_ids(
    service_id: str, dependencies: list[Dependency | DependencyView]
) -> list[str] {
    return [
        dependency.target_id
        for dependency in dependencies
        if dependency.source_id == service_id
    ];
}

def used_by_ids(
    service_id: str, dependencies: list[Dependency | DependencyView]
) -> list[str] {
    return [
        dependency.source_id
        for dependency in dependencies
        if dependency.target_id == service_id
    ];
}

def service_name(services: list[Service], service_id: str) -> str {
    for service in services {
        if service.id == service_id {
            return service.name;
        }
    }
    return service_id;
}

def service_state(services: list[Service], service_id: str) -> str {
    for service in services {
        if service.id == service_id {
            return service.state;
        }
    }
    return "unknown";
}

def names_of(services: list[Service], ids: list[str]) -> str {
    return ", ".join([service_name(services, item) for item in ids]) if ids else "none";
}

def clamp_zoom(value: float) -> float {
    if value < 0.4 {
        return 0.4;
    }
    if value > 2.5 {
        return 2.5;
    }
    return value;
}

def:pub NodeChip(
    label: str, service_id: str, on_select: Callable[[str], None]
) -> JsxElement {
    return
        <button
            type="button"
            className="node-chip"
            onClick={lambda { on_select(service_id); }}
        >
            {label}
        </button>;
}

def:pub DependencyGraph(
    services: list[Service],
    dependencies: list[Dependency | DependencyView],
    selected_service: str,
    on_select: Callable[[str], None]
) -> JsxElement {
    # Pan and zoom: the latest transform lives in a ref because event closures
    # can hold stale state; the state values only drive rendering.
    has zoom: float = 1.0,
        pan_x: float = 0.0,
        pan_y: float = 0.0,
        dragging: bool = False;
    has view_ref: Ref[dict] = Ref({"zoom": 1.0, "x": 0.0, "y": 0.0});
    has drag_ref: Ref[dict] = Ref(
        {"active": False, "sx": 0.0, "sy": 0.0, "ox": 0.0, "oy": 0.0}
    );
    has viewport: Ref[any] = Ref(None);

    def apply_view(next_zoom: float, next_x: float, next_y: float) -> None {
        clamped = clamp_zoom(next_zoom);
        view_ref.current["zoom"] = clamped;
        view_ref.current["x"] = next_x;
        view_ref.current["y"] = next_y;
        zoom = clamped;
        pan_x = next_x;
        pan_y = next_y;
    }
    def zoom_by(factor: float, pivot_x: float, pivot_y: float) -> None {
        current = view_ref.current;
        next_zoom = clamp_zoom(current["zoom"] * factor);
        ratio = next_zoom / current["zoom"];
        apply_view(
            next_zoom,
            pivot_x - (pivot_x - current["x"]) * ratio,
            pivot_y - (pivot_y - current["y"]) * ratio
        );
    }
    def zoom_center(factor: float) -> None {
        surface = viewport.current;
        if surface is not None {
            zoom_by(factor, surface.clientWidth / 2, surface.clientHeight / 2);
        }
    }
    def reset_view -> None {
        apply_view(1.0, 0.0, 0.0);
    }
    def start_drag(event: any) -> None {
        target = event.target;
        if event.button != 0
        or target.closest(".service-node")
        or target.closest(".graph-tools") {
            return;
        }
        drag_ref.current = {
            "active": True,
            "sx": event.clientX,
            "sy": event.clientY,
            "ox": view_ref.current["x"],
            "oy": view_ref.current["y"]
        };
        event.currentTarget.setPointerCapture(event.pointerId);
        dragging = True;
    }
    def move_drag(event: any) -> None {
        drag = drag_ref.current;
        if not drag["active"] {
            return;
        }
        apply_view(
            view_ref.current["zoom"],
            drag["ox"] + event.clientX - drag["sx"],
            drag["oy"] + event.clientY - drag["sy"]
        );
    }
    def end_drag(event: any) -> None {
        drag_ref.current["active"] = False;
        dragging = False;
    }
    def on_key(event: any) -> None {
        if event.target != event.currentTarget {
            return;
        }
        step = 40.0;
        current = view_ref.current;
        if event.key == "+" or event.key == "=" {
            event.preventDefault();
            zoom_center(1.2);
        } elif event.key == "-" or event.key == "_" {
            event.preventDefault();
            zoom_center(1 / 1.2);
        } elif event.key == "0" {
            event.preventDefault();
            reset_view();
        } elif event.key == "ArrowLeft" {
            event.preventDefault();
            apply_view(current["zoom"], current["x"] + step, current["y"]);
        } elif event.key == "ArrowRight" {
            event.preventDefault();
            apply_view(current["zoom"], current["x"] - step, current["y"]);
        } elif event.key == "ArrowUp" {
            event.preventDefault();
            apply_view(current["zoom"], current["x"], current["y"] + step);
        } elif event.key == "ArrowDown" {
            event.preventDefault();
            apply_view(current["zoom"], current["x"], current["y"] - step);
        }
    }
    def on_wheel(event: any) -> None {
        # Zoom only with Ctrl/Cmd (or a trackpad pinch) so normal scrolling still moves the page.
        if not (event.ctrlKey or event.metaKey) {
            return;
        }
        event.preventDefault();
        box = viewport.current.getBoundingClientRect();
        zoom_by(
            0.9 if event.deltaY > 0 else 1.1,
            event.clientX - box.left,
            event.clientY - box.top
        );
    }

    can with entry {
        # React wheel handlers are passive, so attach a native one that may call preventDefault.
        surface = viewport.current;
        if surface is not None {
            surface.addEventListener("wheel", on_wheel, {"passive": False});
        }
    }

    return
        <section className="panel graph-panel" aria-labelledby="graph-title">
            <div className="panel-heading">
                <div>
                    <p className="section-kicker">Known topology</p>
                    <h2 id="graph-title">Service dependency graph</h2>
                </div>
            </div>
            <div className="graph-legend">
                <span>Solid: documented</span>
                <span className="discovered-key">Dashed: trace-backed discovery</span>
            </div>
            <div
                className={"graph-scroll is-dragging" if dragging else "graph-scroll"}
                ref={viewport}
                tabIndex={0}
                role="region"
                aria-label="Service graph. Drag to pan. Use plus and minus to zoom, zero to reset, arrow keys to move."
                onPointerDown={start_drag}
                onPointerMove={move_drag}
                onPointerUp={end_drag}
                onPointerCancel={end_drag}
                onKeyDown={on_key}
            >
                <div
                    className="graph-tools"
                    role="group"
                    aria-label="Graph zoom controls"
                >
                    <button
                        type="button"
                        className="graph-tool"
                        aria-label="Zoom in"
                        onClick={lambda { zoom_center(1.25); }}
                    >
                        +
                    </button>
                    <button
                        type="button"
                        className="graph-tool"
                        aria-label="Zoom out"
                        onClick={lambda { zoom_center(1 / 1.25); }}
                    >
                        −
                    </button>
                    <button
                        type="button"
                        className="graph-tool graph-tool-reset"
                        aria-label="Reset view"
                        onClick={lambda { reset_view(); }}
                    >
                        Reset
                    </button>
                </div>
                <div
                    className="graph-stage"
                    style={{
                        "transform": f"translate({pan_x}px, {pan_y}px) scale({zoom})",
                        "transformOrigin": "0 0"
                    }}
                >
                    <div className="graph-canvas">
                        <svg
                            className="graph-lines"
                            viewBox="0 0 1000 440"
                            preserveAspectRatio="none"
                            aria-hidden="true"
                        >
                            <defs>
                                <marker
                                    id="documented-arrow"
                                    markerWidth="8"
                                    markerHeight="8"
                                    refX="7"
                                    refY="4"
                                    orient="auto"
                                >
                                    <path d="M0,0 L8,4 L0,8 Z"/>
                                </marker>
                                <marker
                                    id="discovered-arrow"
                                    markerWidth="8"
                                    markerHeight="8"
                                    refX="7"
                                    refY="4"
                                    orient="auto"
                                >
                                    <path d="M0,0 L8,4 L0,8 Z"/>
                                </marker>
                            </defs>
                            {[
                                <GraphEdge
                                    key={f"{dependency.source_id}-{dependency.target_id}"}
                                    dependency={dependency}
                                    active={dependency.source_id == selected_service
                                    or dependency.target_id == selected_service}
                                /> for dependency in dependencies
                            ]}
                        </svg>
                        {[
                            <ServiceNode
                                key={service.id}
                                service={service}
                                selected={service.id == selected_service}
                                on_select={on_select}
                                related={related_ids(service.id, dependencies)}
                                summary={f"{service.name}: {service.state}. Depends on: {names_of(
                                    services, depends_on_ids(service.id, dependencies)
                                )}. Used by: {names_of(
                                    services, used_by_ids(service.id, dependencies)
                                )}."}
                            /> for service in services
                        ]}
                    </div>
                </div>
            </div>
            <p className="graph-hint">
                Drag the background to pan. Ctrl + scroll, pinch, or the + and − buttons zoom.
            </p>
            <div className="node-focus" aria-live="polite">
                <p className="section-kicker">Selected service</p>
                {selected_service == ""
                and <p className="muted">
                    Hover a node to trace its links, or select one to see what it depends on and what depends on it.
                </p>}
                {selected_service != ""
                and <div>
                    <p className="node-focus-title">
                        <strong>{service_name(services, selected_service)}</strong>
                        <span
                            className={f"node-focus-state focus-{service_state(
                                services, selected_service
                            )}"}
                        >
                            {service_state(services, selected_service)}
                        </span>
                    </p>
                    <div className="node-focus-row">
                        <span className="node-focus-label">Depends on</span>
                        {[
                            <NodeChip
                                key={item}
                                label={service_name(services, item)}
                                service_id={item}
                                on_select={on_select}
                            />
                            for item in depends_on_ids(selected_service, dependencies)
                        ]}
                        {len(depends_on_ids(selected_service, dependencies)) == 0
                        and <span className="muted">None</span>}
                    </div>
                    <div className="node-focus-row">
                        <span className="node-focus-label">Used by</span>
                        {[
                            <NodeChip
                                key={item}
                                label={service_name(services, item)}
                                service_id={item}
                                on_select={on_select}
                            /> for item in used_by_ids(selected_service, dependencies)
                        ]}
                        {len(used_by_ids(selected_service, dependencies)) == 0
                        and <span className="muted">None</span>}
                    </div>
                </div>}
            </div>
            <details className="relationship-details">
                <summary>Read {len(dependencies)} known relationships</summary>
                <ul>
                    {[
                        <li key={index}>
                            {dependency.source_id}{" "}
                            depends on{" "}
                            {dependency.target_id}{" "}
                            <span>({dependency.kind})</span>
                            {dependency.kind == "discovered"
                            and <small>
                                Evidence: {", ".join(dependency.evidence_ids)}
                            </small>}
                        </li> for (index, dependency) in enumerate(dependencies)
                    ]}
                </ul>
            </details>
            <p className="panel-footnote">
                Arrows point from a service to its dependency. Select a node to scan, analyze, or preview its recovery.
            </p>
        </section>;
}
