"""Recovery preview displays before/after observations without applying repairs."""
import from ..atoms.StatusBadge { StatusBadge }
import from ..atoms.ActionButton { ActionButton }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..models.view_models { RecoveryView, has_result, is_busy }

def:pub RecoveryPanel(
    result: RecoveryView,
    service_id: str,
    disabled: bool,
    on_preview: Callable[[], None]
) -> JsxElement {
    <section
        className="panel recovery-panel"
        aria-labelledby="recovery-title"
        aria-busy={is_busy(result.feedback.status)}
    >
        <div className="panel-heading">
            <div>
                <p className="section-kicker">Non-destructive verification</p>
                <h2 id="recovery-title">Recovery preview</h2>
            </div>
            <StatusBadge status={result.feedback.status}/>
        </div>
        <p className="helper-text">
            Candidate service:{" "}
            <strong>{service_id}</strong>
            . Preview does not apply a repair to the active incident.
        </p>
        <ActionButton
            label="Preview recovery"
            on_click={on_preview}
            busy={is_busy(result.feedback.status)}
            disabled={disabled}
        />
        <PanelFeedback
            feedback={result.feedback}
            idle_message="Compare a candidate repair against the current simulation."
        />
        {has_result(result.feedback.status)
            and <div className="recovery-results">
                <h3>Candidate repair</h3>
                <p>{result.repair}</p>
                <div className="table-scroll">
                    <table className="comparison-table">
                        <caption>Service health before and after the preview</caption>
                        <thead>
                            <tr>
                                <th scope="col">Service</th>
                                <th scope="col">Before</th>
                                <th scope="col">After</th>
                            </tr>
                        </thead>
                        <tbody>
                            {[
                                <tr key={row.service_id}>
                                    <th scope="row">{row.service_id}</th>
                                    <td>{row.before}</td>
                                    <td>{row.after}</td>
                                </tr> for row in result.rows
                            ]}
                        </tbody>
                    </table>
                </div>
                <h3>Verification outcome</h3>
                <p role="status">{result.outcome}</p>
            </div>}
    </section>
}
