"""Prepared surface for evidence-driven agent output."""

def:pub InvestigationPanel(status: str) -> JsxElement {
    return <section
        className="panel investigation-panel"
        aria-labelledby="investigation-title"
    >
        <div className="panel-heading">
            <div>
                <p className="section-kicker">Evidence before inference</p>
                <h2 id="investigation-title">AI investigation</h2>
            </div>
            <span className="status-tag idle">Idle</span>
        </div>
        <div className="investigation-status">
            <span className="pulse-ring"></span>
            <p>{status}</p>
        </div>
        <ol className="timeline">
            <li>
                <span>01</span>
                <div>
                    <strong>Tool-call timeline</strong>
                    <small>Waiting for diagnostic tools</small>
                </div>
            </li>
            <li>
                <span>02</span>
                <div>
                    <strong>Observed evidence</strong>
                    <small>No observations collected</small>
                </div>
            </li>
            <li>
                <span>03</span>
                <div>
                    <strong>Candidate causes</strong>
                    <small>No model output</small>
                </div>
            </li>
        </ol>
        <div className="empty-result">
            <strong>Proposed explanation</strong>
            <p>
                Not implemented yet. This area will display evidence-cited Investigator output.
            </p>
        </div>
    </section>;
}
