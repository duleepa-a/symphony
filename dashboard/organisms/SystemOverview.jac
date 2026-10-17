"""Current-run service and verified-finding counters."""
import type from ..models.view_models { OverviewView }
import from ..atoms.MetricCard { MetricCard }

def:pub SystemOverview(summary: OverviewView, run_id: str) -> JsxElement {
    return
        <section className="overview" aria-labelledby="overview-title">
            <div className="section-heading">
                <div>
                    <p className="section-kicker">Current topology</p>
                    <h2 id="overview-title">System overview</h2>
                </div>
                <p>Simulation run: {run_id}</p>
            </div>
            <div className="metric-grid">
                <MetricCard
                    label="Total services"
                    value={summary.total_services}
                    tone="neutral"
                />
                <MetricCard
                    label="Healthy"
                    value={summary.healthy_services}
                    tone="healthy"
                />
                <MetricCard
                    label="Degraded"
                    value={summary.degraded_services}
                    tone="warning"
                />
                <MetricCard
                    label="Failed"
                    value={summary.failed_services}
                    tone="failed"
                />
                <MetricCard
                    label="Discovered edges"
                    value={summary.discovered_dependencies}
                    tone="signal"
                />
                <MetricCard
                    label="Returned advisories"
                    value={summary.vulnerability_findings}
                    tone="warning"
                />
            </div>
        </section>;
}
