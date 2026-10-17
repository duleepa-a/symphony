"""System-wide service and finding counters."""

import from ..contracts { DashboardSummary }

def MetricCard(label: str, value: int, tone: str) -> JsxElement {
    <article className={f"metric-card {tone}"}>
        <span className="metric-label">{label}</span>
        <strong>{value}</strong>
        <span className="metric-rule"></span>
    </article>
}

def:pub SystemOverview(summary: DashboardSummary) -> JsxElement {
    <section className="overview" aria-labelledby="overview-title">
        <div className="section-heading">
            <div>
                <p className="section-kicker">Current topology</p>
                <h2 id="overview-title">System overview</h2>
            </div>
            <p>Documented architecture · initial state</p>
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
            <MetricCard label="Failed" value={summary.failed_services} tone="failed"/>
            <MetricCard
                label="Discovered edges"
                value={summary.discovered_dependencies}
                tone="signal"
            />
            <MetricCard
                label="Known findings"
                value={summary.vulnerability_findings}
                tone="warning"
            />
        </div>
    </section>
}
