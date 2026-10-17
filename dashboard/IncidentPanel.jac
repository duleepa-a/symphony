"""Incident selection and simulation controls."""

def:pub IncidentPanel(
    selected_incident: str,
    busy: bool,
    on_incident_change: Callable[[str], None],
    on_trigger: Callable[[], None],
    on_reset: Callable[[], None],
    on_investigate: Callable[[], None]
) -> JsxElement {
    <section className="panel incident-panel" aria-labelledby="incident-title">
        <div className="panel-heading">
            <div>
                <p className="section-kicker">Controlled experiment</p>
                <h2 id="incident-title">Incident controls</h2>
            </div>
            <span className="status-tag pending">Not connected</span>
        </div>
        <label className="field-label" htmlFor="incident-select">Scenario</label>
        <select
            id="incident-select"
            value={selected_incident}
            disabled={busy}
            onChange={lambda (e: ChangeEvent) { on_incident_change(e.target.value); }}
        >
            <option value="normal">Normal operation</option>
            <option value="auth_outage">Auth outage</option>
            <option value="payment_outage">Payment outage</option>
        </select>
        <div className="button-row">
            <button className="button danger" disabled={busy} onClick={on_trigger}>
                Trigger incident
            </button>
            <button className="button secondary" disabled={busy} onClick={on_reset}>
                Reset
            </button>
            <button className="button primary" disabled={busy} onClick={on_investigate}>
                Investigate
            </button>
        </div>
        <p className="helper-text">
            Simulator and Investigator return explicit placeholder statuses in this phase.
        </p>
    </section>
}
