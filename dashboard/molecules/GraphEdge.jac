"""Edges follow the computed node layout so documented and discovered links stay aligned."""
import type from ...contracts { Dependency }
import from ..models.view_models { DependencyView, GraphLayout }

def:pub GraphEdge(
    dependency: Dependency | DependencyView, layout: GraphLayout, hovered: str
) -> JsxElement {
    if dependency.source_id not in layout.positions
    or dependency.target_id not in layout.positions {
        return <g/>;
    }
    source = layout.positions[dependency.source_id];
    target = layout.positions[dependency.target_id];
    sx = source.x_pct * 10.0 + 60.0;
    sy = source.y_pct * layout.height / 100.0;
    tx = target.x_pct * 10.0 - 65.0;
    ty = target.y_pct * layout.height / 100.0;
    touches = hovered != ""
    and (dependency.source_id == hovered or dependency.target_id == hovered);
    state_class = " edge-active" if touches else (" edge-dim" if hovered != "" else "");
    return
        <path
            d={f"M{sx} {sy} L{tx} {ty}"}
            className={f"dependency-edge edge-{dependency.kind}{state_class}"}
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
        </path>;
}
