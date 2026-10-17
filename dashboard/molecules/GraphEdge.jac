"""Fixed service coordinates keep documented and discovered edges aligned."""
import from ...contracts { Dependency }

def:pub GraphEdge(dependency: Dependency) -> JsxElement {
    coordinates = {
        "frontend": (120, 220),
        "api_gateway": (380, 220),
        "payment": (650, 106),
        "catalog": (650, 326),
        "auth": (880, 66),
        "database": (880, 326)
    };
    if dependency.source_id not in coordinates
        or dependency.target_id not in coordinates {
        return <g/>;
    }
    source = coordinates[dependency.source_id];
    target = coordinates[dependency.target_id];
    d = f"M{source[0] + 60} {source[1]} L{target[0] - 65} {target[1]}";
    <path
        d={d}
        className={f"dependency-edge edge-{dependency.kind}"}
        data-kind={dependency.kind}
        data-source={dependency.source_id}
        data-target={dependency.target_id}
        markerEnd={"url(#discovered-arrow)"
            if dependency.kind == "discovered"
            else "url(#documented-arrow)"}
    >
        <title>
            {dependency.source_id} depends on {dependency.target_id} ({dependency.kind})
        </title>
    </path>
}
