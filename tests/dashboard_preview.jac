"""Fixture controls for the root dashboard_preview.jac entry. Never imported from main."""
import from "@jac/runtime" { __jacClearCache }
sv import from .dashboard_preview_server { fixture_mode }

def:pub FixtureToolbar() -> JsxElement {
    has mode: str = "completed",
        applied: str = "completed";
    async def apply_mode -> None {
        __jacClearCache();
        reply: any = await fixture_mode(mode);
        applied = reply if isinstance(reply, str) else "Fixture request failed; retry";
    }
    return
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
        </aside>;
}
