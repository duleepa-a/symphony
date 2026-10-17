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
    investigation_busy: bool,
    on_full_assessment: Callable[[], None],
    full_assessment_busy: bool,
    automation_feedback: PanelStatus,
    service_mode: str = "mock"
) -> JsxElement {
    busy = is_busy(feedback.status);
    real_mode = service_mode in ["real", "docker", "remote"];
    return
        <section
            className="panel incident-panel"
            aria-labelledby="incident-title"
            aria-busy={busy or full_assessment_busy}
        >
            <div className="panel-heading">
                <div>
                    <p className="section-kicker">
                        {"Live automation" if real_mode else "Controlled experiment"}
                    </p>
                    <h2 id="incident-title">
                        {"Assessment controls" if real_mode else "Incident controls"}
                    </h2>
                </div>
                <StatusBadge
                    status={automation_feedback.status
                        if real_mode
                        else feedback.status}
                />
            </div>
            {if not real_mode {
                <label className="field-label" htmlFor="incident-select">
                    Scenario
                </label>
                <select
                    id="incident-select"
                    value={selected_incident}
                    disabled={busy or full_assessment_busy}
                    onChange={lambda (e: ChangeEvent) { on_incident_change(
                        e.target.value
                    ); }}
                >
                    <option value="normal">Normal operation</option>
                    <option value="auth_outage">Auth outage</option>
                    <option value="payment_outage">Payment outage</option>
                </select>
            }}
            <div className={"button-row real-actions" if real_mode else "button-row"}>
                {if not real_mode {
                    <ActionButton
                        label="Trigger incident"
                        on_click={on_trigger}
                        busy={busy}
                        disabled={full_assessment_busy}
                        tone="danger"
                    />
                    <ActionButton
                        label="Reset simulation"
                        on_click={on_reset}
                        disabled={busy or full_assessment_busy}
                        tone="secondary"
                    />
                }}
                <ActionButton
                    label="Investigate"
                    on_click={on_investigate}
                    busy={investigation_busy}
                    disabled={busy or full_assessment_busy}
                />
                <ActionButton
                    label="Run full assessment"
                    on_click={on_full_assessment}
                    busy={full_assessment_busy}
                    disabled={busy or investigation_busy}
                    tone="secondary"
                />
            </div>
            <PanelFeedback
                feedback={automation_feedback if real_mode else feedback}
                idle_message={"Real service state is controlled through Docker. Symphony polls service health automatically every 10 seconds."
                    if real_mode
                    else "Choose a scenario. Only connected simulation operations can change service health."}
            />
            {not real_mode
            and automation_feedback.status != "idle"
            and <PanelFeedback feedback={automation_feedback} idle_message=""/>}
            <p className="helper-text">
                {"Investigation reads live health, logs, and traces. Predetermined incident scenarios are not available in real mode."
                    if real_mode
                    else "Reset invalidates all investigation, scan, impact, and recovery results from the previous run."}
            </p>
        </section>;
}
