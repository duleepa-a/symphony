"""Explain model assessment alongside the independent rule-based priority."""
import from ..models.view_models { SecurityAssessmentView, has_result, is_busy }
import from ..atoms.ActionButton { ActionButton }
import from ..atoms.StatusBadge { StatusBadge }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..molecules.AssessedFinding { AssessedFinding }
def:pub SecurityAssessmentPanel(
    result: SecurityAssessmentView,
    rule_priority: str,
    disabled: bool,
    on_assess: Callable[[], None]
) -> JsxElement {
    return
        <div className="agent-section" aria-busy={is_busy(result.feedback.status)}>
            <div className="panel-heading">
                <h3>Security Analyst</h3>
                <StatusBadge status={result.feedback.status}/>
            </div>
            <p className="disclosure">
                Model-generated assessment · current scan required
            </p>
            <ActionButton
                label="Assess scan risk"
                on_click={on_assess}
                busy={is_busy(result.feedback.status)}
                disabled={disabled}
            />
            <PanelFeedback
                feedback={result.feedback}
                idle_message="Scan a service, then request an evidence-cited risk assessment."
            />
            <p>Deterministic rule-based priority: <strong>{rule_priority}</strong></p>
            {has_result(result.feedback.status)
            and <div>
                <p>Model priority: <strong>{result.priority}</strong></p>
                {result.priority_lower
                and <p className="package-error" role="status">
                    Model priority is lower than the deterministic priority. Review both; the rule-based result remains available.
                </p>}
                {(
                    result.scan_status != "completed"
                    or result.feedback.status == "partial"
                )
                and <p className="package-error" role="status">
                    Scan coverage is incomplete. This assessment is not an all-clear.
                </p>}
                <p>{result.explanation}</p>
                <ul className="advisory-list">
                    {[
                        <AssessedFinding key={index} finding={finding}/>
                        for (index, finding) in enumerate(result.findings)
                    ]}
                </ul>
                {not result.findings
                and result.scan_status == "completed"
                and <p>
                    No findings in the completed scan. This does not establish that the service is free of all vulnerabilities.
                </p>}
                <p className="muted">
                    Potentially affected dependents: {", ".join(result.dependents)
                        if result.dependents
                        else "None in the known graph"}
                </p>
            </div>}
            <p className="helper-text">
                Dependency reach alone does not establish vulnerability or compromise. Rule-based impact remains available if the agent fails.
            </p>
        </div>;
}
