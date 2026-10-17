"""Recovery preview displays before/after observations without applying repairs."""
import from .RecoveryProposalPanel { RecoveryProposalPanel }
import from ..molecules.RecoveryComparison { RecoveryComparison }
import from ..models.view_models { RecoveryProposalView }
import from ..atoms.StatusBadge { StatusBadge }
import from ..atoms.ActionButton { ActionButton }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..models.view_models { RecoveryView, has_result, is_busy }

def:pub RecoveryPanel(
    result: RecoveryView,
    service_id: str,
    disabled: bool,
    on_preview: Callable[[], None],
    proposal: RecoveryProposalView,
    proposal_disabled: bool,
    on_propose: Callable[[], None]
) -> JsxElement {
    return
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
                <RecoveryComparison result={result}/>
            </div>}
            <RecoveryProposalPanel
                result={proposal}
                disabled={disabled or proposal_disabled}
                on_propose={on_propose}
            />
        </section>;
}
