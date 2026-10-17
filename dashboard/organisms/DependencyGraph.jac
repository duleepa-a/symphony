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
                className="graph-scroll"
                tabIndex={0}
                role="region"
                aria-label="Service graph; scroll horizontally on smaller screens"
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
