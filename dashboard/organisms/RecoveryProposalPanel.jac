"""Separate model-authored repair proposals from copied-state verification."""
import from ..models.view_models { RecoveryProposalView, has_result, is_busy }
import from ..atoms.ActionButton { ActionButton }
import from ..atoms.StatusBadge { StatusBadge }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..molecules.RecoveryComparison { RecoveryComparison }
def:pub RecoveryProposalPanel(
    result: RecoveryProposalView, disabled: bool, on_propose: Callable[[], None]
) -> JsxElement {
    return
        <div className="agent-section" aria-busy={is_busy(result.feedback.status)}>
            <div className="panel-heading">
                <h3>Recovery agent</h3>
                <StatusBadge status={result.feedback.status}/>
            </div>
            <p className="disclosure">
                Model-generated repair proposal · current investigation required
            </p>
            <ActionButton
                label="Propose recovery"
                on_click={on_propose}
                busy={is_busy(result.feedback.status)}
                disabled={disabled}
            />
            <PanelFeedback
                feedback={result.feedback}
                idle_message="Run INVESTIGATE and wait for evidence to appear before requesting a repair proposal. Changing or resetting the incident clears its investigation."
            />
            {has_result(result.feedback.status)
            and <div>
                <h4>Proposed target and action</h4>
                <p>{result.target} · {result.action}</p>
                <p>{result.rationale}</p>
                <p className="muted">
                    Cited diagnostic evidence: {", ".join(result.citations)}
                </p>
                <RecoveryComparison result={result.preview}/>
            </div>}
            <p className="helper-text">
                The simulator determines the outcome. A proposal never applies a repair to the active incident.
            </p>
        </div>;
}
