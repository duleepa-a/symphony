"""Reusable deterministic verification table for manual and proposed repairs."""
import from ..models.view_models { RecoveryView }
def:pub RecoveryComparison(result: RecoveryView) -> JsxElement {
    return
        <div className="recovery-results">
            <p className="disclosure">
                {"Observed real-service state · repair not applied"
                    if result.source == "real_service_health"
                    else "Deterministic simulator verification · preview only"}
            </p>
            {result.verification_note
            and <p className="helper-text">{result.verification_note}</p>}
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
        </div>;
}
