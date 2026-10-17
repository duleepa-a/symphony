"""One labeled metric in the system overview."""
def:pub MetricCard(label: str, value: int, tone: str) -> JsxElement {
    return
        <article className={f"metric-card {tone}"}>
            <span className="metric-label">{label}</span>
            <strong>{value}</strong>
            <span className="metric-rule"></span>
        </article>;
}
