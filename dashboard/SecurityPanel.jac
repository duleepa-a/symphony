"""Real-lookup scanner surface with truthful initial state."""

import from ..contracts { Service }

def:pub SecurityPanel(
    services: list[Service],
    selected_service: str,
    busy: bool,
    on_service_change: Callable[[str], None],
    on_scan: Callable[[], None]
) -> JsxElement {
    return <section className="panel security-panel" aria-labelledby="security-title">
        <div className="panel-heading">
            <div>
                <p className="section-kicker">OSV.dev intelligence</p>
                <h2 id="security-title">Vulnerability scanning</h2>
            </div>
            <span className="status-tag pending">Adapter ready</span>
        </div>
        <p className="disclosure">Simulated service inventory — real advisory lookup</p>
        <div className="scan-controls">
            <div>
                <label className="field-label" htmlFor="service-select">
                    Service inventory
                </label>
                <select
                    id="service-select"
                    value={selected_service}
                    disabled={busy}
                    onChange={lambda (e: ChangeEvent) { on_service_change(
                        e.target.value
                    ); }}
                >
                    {[
                        <option key={service.id} value={service.id}>
                            {service.name}
                        </option> for service in services
                    ]}
                </select>
            </div>
            <button className="button primary" disabled={busy} onClick={on_scan}>
                Scan dependencies
            </button>
        </div>
        <div
            className="scan-table"
            role="table"
            aria-label="Vulnerability scan results"
        >
            <div className="scan-row scan-header" role="row">
                <span>Package</span>
                <span>Version</span>
                <span>Advisory</span>
                <span>Status</span>
            </div>
            <div className="scan-empty">
                <span className="scan-crosshair">+</span>
                <div>
                    <strong>No scan has run</strong>
                    <p>
                        Connect the OSV server adapter to populate verified advisories.
                    </p>
                </div>
            </div>
        </div>
    </section>;
}
