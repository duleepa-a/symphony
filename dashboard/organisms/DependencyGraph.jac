"""Graph presentation consumes public dependencies, never the simulator's true graph."""
import type from ...contracts { Dependency }
import from ..models.view_models { DependencyView, graph_layout }
import from ...contracts { Service }
import from ..molecules.ServiceNode { ServiceNode }
import from ..molecules.GraphEdge { GraphEdge }

def:pub DependencyGraph(
    services: list[Service],
    dependencies: list[Dependency | DependencyView],
    selected_service: str,
    on_select: Callable[[str], None]
) -> JsxElement {
    has hovered: str = "";

    layout = graph_layout(services, dependencies);
    related = [
        dependency.target_id
        for dependency in dependencies
        if dependency.source_id == hovered
    ] + [
        dependency.source_id
        for dependency in dependencies
        if dependency.target_id == hovered
    ];
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
                style={{"height": f"{layout.height}px"}}
                tabIndex={0}
                role="region"
                aria-label="Service graph; scroll horizontally on smaller screens"
            >
                <div
                    className="graph-canvas"
                    style={{
                        "height": f"{layout.height}px",
                        "--mh": f"{layout.mobile_height}px"
                    }}
                >
                    <svg
                        className="graph-lines"
                        viewBox={f"0 0 1000 {layout.height}"}
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
                                layout={layout}
                                hovered={hovered}
                            /> for dependency in dependencies
                        ]}
                    </svg>
                    {[
                        <ServiceNode
                            key={service.id}
                            service={service}
                            selected={service.id == selected_service}
                            on_select={on_select}
                            position={layout.positions[service.id]}
                            dim={hovered != ""
                            and service.id != hovered
                            and service.id not in related}
                            on_hover={lambda (service_id: str) { hovered = service_id; }}
                        /> for service in services
                    ]}
                </div>
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
