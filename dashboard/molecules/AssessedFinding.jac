"""Model-authored risk text with explicit advisory provenance."""
import from ..models.view_models { AssessedFindingView }
def:pub AssessedFinding(finding: AssessedFindingView) -> JsxElement {
    return
        <li className="package-result">
            <h4>{finding.advisory_id} · {finding.package}</h4>
            <p>{finding.risk}</p>
            <p className="muted">Cited advisories: {", ".join(finding.citations)}</p>
        </li>;
}
