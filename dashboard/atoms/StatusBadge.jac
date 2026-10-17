"""Small status indicator shared by dashboard panels."""
def:pub StatusBadge(status: str) -> JsxElement {
    labels = {
        "idle": "Ready",
        "loading": "Loading",
        "running": "Running",
        "completed": "Completed",
        "partial": "Partial results",
        "failed": "Failed",
        "not_implemented": "Not connected",
        "simulation_not_connected": "Not connected"
    };
    return
        <span className={f"status-tag status-{status}"}>
            {labels[status] if status in labels else status}
        </span>;
}
