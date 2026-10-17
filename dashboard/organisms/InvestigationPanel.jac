"""Evidence and ranked findings are rendered only from returned operation data."""
import from ..atoms.StatusBadge { StatusBadge }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..molecules.EmptyState { EmptyState }
import from ..models.view_models { InvestigationView, has_result, is_busy }

def:pub InvestigationPanel(result: InvestigationView) -> JsxElement {
    return
        <section
            className="panel investigation-panel"
            aria-labelledby="investigation-title"
            aria-busy={is_busy(result.feedback.status)}
        >
            <div className="panel-heading">
                <div>
                    <p className="section-kicker">Evidence before inference</p>
                    <h2 id="investigation-title">AI investigation</h2>
                </div>
                <StatusBadge status={result.feedback.status}/>
            </div>
            <PanelFeedback
                feedback={result.feedback}
                idle_message="Start an investigation to collect diagnostic evidence."
            />
            {has_result(result.feedback.status)
            and <div className="investigation-results">
                <h3>Tool-call timeline</h3>
                {result.timeline
                and <ol className="timeline">
                    {[
                        <li key={index}>
                            <span>{index + 1}</span>
                            <p>{step}</p>
                        </li> for (index, step) in enumerate(result.timeline)
                    ]}
                </ol>}
                {not result.timeline
                and <p className="muted">No tool calls were reported.</p>}
                <h3>Observed evidence</h3>
                {result.evidence
                and <ul className="evidence-list">
                    {[
                        <li key={index}>
                            <strong>{item.id or f"Observation {index + 1}"}</strong>
                            <small>{item.tool} {item.service_id}</small>
                            <p>{item.observation}</p>
                        </li> for (index, item) in enumerate(result.evidence)
                    ]}
                </ul>}
                {not result.evidence
                and <p className="muted">No diagnostic evidence was returned.</p>}
                <h3>Ranked candidate causes</h3>
                {result.candidates
                and <ol className="candidate-list">
                    {[
                        <li key={index}>{cause}</li>
                        for (index, cause) in enumerate(result.candidates)
                    ]}
                </ol>}
                {not result.candidates
                and <p className="muted">No supported candidate was identified.</p>}
                <h3>Discovered relationships</h3>
                {result.dependencies
                and <ul className="relationship-list">
                    {[
                        <li key={index}>
                            <strong>
                                {dependency.source_id} → {dependency.target_id}
                            </strong>
                            <small>
                                Trace evidence: {", ".join(dependency.evidence_ids)}
                            </small>
                        </li> for (index, dependency) in enumerate(result.dependencies)
                    ]}
                </ul>}
                {not result.dependencies
                and <p className="muted">
                    No evidence-backed relationships discovered.
                </p>}
                <h3>Explanation</h3>
                <p className="explanation">
                    {result.explanation or "No explanation was supplied."}
                </p>
            </div>}
            {not has_result(result.feedback.status)
            and <EmptyState
                title="Awaiting diagnostic evidence"
                description="Conclusions and relationships appear here only after a connected investigation returns evidence."
            />}
        </section>;
}
