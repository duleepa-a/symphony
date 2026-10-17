"""Product identity and environment signal."""

def:pub TopBar(mode: str = "mock") -> JsxElement {
    live = mode in ["real", "docker", "remote"];
    return
        <header className="topbar">
            <div className="brand-lockup">
                <div className="brand-mark" aria-hidden="true">
                    <span></span>
                    <span></span>
                    <span></span>
                    <span></span>
                </div>
                <div>
                    <p className="eyebrow">
                        Agentic reliability &amp; security intelligence
                    </p>
                    <h1>SYMPHONY</h1>
                </div>
            </div>
            <div className="environment-chip">
                <span className="live-dot"></span>
                {"Real services" if live else "Simulation workspace"}
            </div>
        </header>;
}
