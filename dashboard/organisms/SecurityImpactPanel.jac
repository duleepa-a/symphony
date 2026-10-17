"""Operational reachability is presented as potential exposure, not compromise."""
import from ..atoms.StatusBadge { StatusBadge }
import from ..atoms.ActionButton { ActionButton }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..models.view_models { ImpactView, has_result, is_busy }

def:pub SecurityImpactPanel(
    result: ImpactView, service_id: str, disabled: bool, on_analyze: Callable[[], None]
) -> JsxElement {
    return
        <section
            className="panel impact-panel"
            aria-labelledby="impact-title"
            aria-busy={is_busy(result.feedback.status)}
        >
            <div className="panel-heading">
                <div>
                    <p className="section-kicker">Known relationship reach</p>
                    <h2 id="impact-title">Security impact</h2>
                </div>
                <StatusBadge status={result.feedback.status}/>
            </div>
            <p className="helper-text">
                Selected service:{" "}
                <strong>{service_id}</strong>
                . Change it in the graph or service inventory selector.
            </p>
            <ActionButton
                label="Analyze potential exposure"
                on_click={on_analyze}
                busy={is_busy(result.feedback.status)}
                disabled={disabled}
            />
            <PanelFeedback
                feedback={result.feedback}
                idle_message="Analyze which services depend on the selected service."
            />
            {has_result(result.feedback.status)
            and <div className="impact-results">
                <p className="disclosure">
                    {"Observed real-service health + known dependency graph"
                        if result.source == "real_service_health"
                        else "Deterministic simulation topology"}
                </p>
                <h3>Potentially exposed dependents</h3>
                {result.dependents
                and <ul>
                    {[
                        <li key={index}>{name}</li>
                        for (index, name) in enumerate(result.dependents)
                    ]}
                </ul>}
                {not result.dependents
                and <p>No dependent services were found in the known graph.</p>}
                <h3>Relationships used</h3>
                <ul>
                    {[
                        <li key={index}>{relationship}</li>
                        for (index, relationship) in enumerate(result.relationships)
                    ]}
                </ul>
                <p>Priority: <strong>{result.priority}</strong></p>
                <p>{result.exposure}</p>
            </div>}
            <p className="helper-text">
                Dependency reach alone does not establish a vulnerability or compromise in another service.
            </p>
        </section>;
}
