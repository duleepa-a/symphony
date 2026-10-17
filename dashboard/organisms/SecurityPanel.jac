"""Package-level advisory results; failures remain distinct from clean scans."""
import from ...contracts { Service }
import from ..atoms.StatusBadge { StatusBadge }
import from ..atoms.ActionButton { ActionButton }
import from ..molecules.PanelFeedback { PanelFeedback }
import from ..molecules.EmptyState { EmptyState }
import from ..models.view_models { ScanView, PackageView, has_result, is_busy }

def PackageResult(package_result: PackageView) -> JsxElement {
    return
        <article className="package-result">
            <div className="package-heading">
                <div>
                    <h3>
                        {package_result.name}{" "}
                        <small>{package_result.version}</small>
                    </h3>
                    <p className="muted">{package_result.ecosystem}</p>
                </div>
                <StatusBadge status={package_result.status}/>
            </div>
            {package_result.error
            and <p role="alert" className="package-error">{package_result.error}</p>}
            {package_result.advisories
            and <ul className="advisory-list">
                {[
                    <li key={index}>
                        <div className="advisory-heading">
                            {advisory.url
                            and <a
                                href={advisory.url}
                                target="_blank"
                                rel="noopener noreferrer"
                            >
                                {advisory.id}
                                <span className="sr-only"> (opens in new tab)</span>
                            </a>}
                            {not advisory.url and <strong>{advisory.id}</strong>}
                            <span
                                className={f"severity severity-{advisory.severity.lower()}"}
                            >
                                Severity: {advisory.severity}
                            </span>
                        </div>
                        <p>{advisory.summary}</p>
                    </li> for (index, advisory) in enumerate(package_result.advisories)
                ]}
            </ul>}
            {not package_result.advisories
            and package_result.status == "completed"
            and not package_result.error
            and <p className="clean-result">
                No advisories returned for this exact package version.
            </p>}
            {not package_result.advisories
            and (package_result.status != "completed" or package_result.error)
            and <p className="muted">
                Lookup incomplete. This package is not verified clean.
            </p>}
        </article>;
}

def:pub SecurityPanel(
    services: list[Service],
    selected_service: str,
    result: ScanView,
    disabled: bool,
    on_service_change: Callable[[str], None],
    on_scan: Callable[[], None]
) -> JsxElement {
    return
        <section
            className="panel security-panel"
            aria-labelledby="security-title"
            aria-busy={is_busy(result.feedback.status)}
        >
            <div className="panel-heading">
                <div>
                    <p className="section-kicker">OSV.dev intelligence</p>
                    <h2 id="security-title">Vulnerability scanning</h2>
                </div>
                <StatusBadge status={result.feedback.status}/>
            </div>
            <p className="disclosure">
                Simulated service inventory — real advisory lookup
            </p>
            <div className="scan-controls">
                <div>
                    <label className="field-label" htmlFor="service-select">
                        Service inventory
                    </label>
                    <select
                        id="service-select"
                        value={selected_service}
                        disabled={disabled}
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
                <ActionButton
                    label="Scan dependencies"
                    on_click={on_scan}
                    busy={is_busy(result.feedback.status)}
                    disabled={disabled}
                />
            </div>
            <PanelFeedback
                feedback={result.feedback}
                idle_message="Select a service to inspect its exact package inventory."
            />
            {has_result(result.feedback.status)
            and <p className="result-summary">
                {result.finding_count} returned advisories · {len(
                    result.packages
                )} package results{result.feedback.status == "partial"
                and " · Incomplete coverage"}
            </p>}
            <div className="package-results">
                {[
                    <PackageResult key={index} package_result={package_result}/>
                    for (index, package_result) in enumerate(result.packages)
                ]}
            </div>
            {not result.packages
            and <EmptyState
                title="No verified scan results"
                description="A completed lookup, an unavailable API, and an unconnected scanner are shown separately."
            />}
        </section>;
}
