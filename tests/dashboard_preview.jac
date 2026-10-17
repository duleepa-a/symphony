"""Explicitly labeled fixture application. Run separately; never import from main."""
import from operations {
    get_dashboard_state,
    start_incident,
    reset_incident,
    run_investigation,
    scan_service_dependencies,
    analyze_security_impact,
    preview_recovery
}
import from .dashboard_preview_server { fixture_mode }
import "../styles.css";
import from ..dashboard.pages.SymphonyDashboard { SymphonyDashboard }

def:pub FixtureToolbar() -> JsxElement {
    has mode: str = "completed",
        applied: str = "completed";
    async def apply_mode -> None {
        applied = await fixture_mode(mode);
    }
    <aside className="fixture-banner">
        <strong>Fixture preview — no live scans or model calls</strong>
        <label htmlFor="fixture-mode">Response case</label>
        <select
            id="fixture-mode"
            value={mode}
            onChange={lambda (e: ChangeEvent) { mode = e.target.value; }}
        >
            {[
                <option key={option} value={option}>{option}</option>
                for option in [
                    "completed",
                    "empty",
                    "partial",
                    "failed",
                    "not_implemented",
                    "slow"
                ]
            ]}
        </select>
        <button onClick={apply_mode}>Apply fixture mode</button>
        <span role="status">Active fixture: {applied}</span>
    </aside>
}

def:pub app -> JsxElement {
    <>
        <FixtureToolbar/>
        <SymphonyDashboard/>
    </>
}
