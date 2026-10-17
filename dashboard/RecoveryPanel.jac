"""Placeholders for graph impact and recovery verification."""

def:pub RecoveryPanel() -> JsxElement {
    return <section className="panel recovery-panel" aria-labelledby="recovery-title">
        <div className="panel-heading">
            <div>
                <p className="section-kicker">Deterministic verification</p>
                <h2 id="recovery-title">Impact &amp; recovery</h2>
            </div>
            <span className="status-tag idle">Planned</span>
        </div>
        <div className="recovery-grid">
            <div>
                <span>Candidate repair</span>
                <strong>Not selected</strong>
            </div>
            <div>
                <span>Before / after</span>
                <strong>Awaiting simulation</strong>
            </div>
            <div>
                <span>Verification</span>
                <strong>Not implemented yet</strong>
            </div>
        </div>
        <p className="helper-text">
            Downstream services will be described as potentially exposed, never compromised without direct evidence.
        </p>
    </section>;
}
