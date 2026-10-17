"""Incident controls composed from shared status and action primitives."""
import from ..atoms.StatusBadge { StatusBadge }
import from ..atoms.ActionButton { ActionButton }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..models.view_models { PanelStatus, is_busy }

def:pub IncidentPanel(
    selected_incident: str,
    feedback: PanelStatus,
    on_incident_change: Callable[[str], None],
    on_trigger: Callable[[], None],
    on_reset: Callable[[], None],
    on_investigate: Callable[[], None],
    investigation_busy: bool
) -> JsxElement {
    busy = is_busy(feedback.status);
    <section
        className="panel incident-panel"
        aria-labelledby="incident-title"
        aria-busy={busy}
    >
        <div className="panel-heading">
            <div>
                <p className="section-kicker">Controlled experiment</p>
                <h2 id="incident-title">Incident controls</h2>
            </div>
            <StatusBadge status={feedback.status}/>
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
            <ActionButton
                label="Trigger incident"
                on_click={on_trigger}
                busy={busy}
                tone="danger"
            />
            <ActionButton
                label="Reset simulation"
                on_click={on_reset}
                disabled={busy}
                tone="secondary"
            />
            <ActionButton
                label="Investigate"
                on_click={on_investigate}
                busy={investigation_busy}
                disabled={busy}
            />
        </div>
        <PanelFeedback
            feedback={feedback}
            idle_message="Choose a scenario. Only connected simulation operations can change service health."
        />
        <p className="helper-text">
            Reset invalidates all investigation, scan, impact, and recovery results from the previous run.
        </p>
    </section>
}
