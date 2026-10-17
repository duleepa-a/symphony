"""Operation feedback never substitutes a failed request with an empty success."""
import from ..models.view_models { PanelStatus }
def:pub PanelFeedback(feedback: PanelStatus, idle_message: str) -> JsxElement {
    return
        <div
            className={f"panel-feedback feedback-{feedback.status}"}
            role={"alert" if feedback.status == "failed" else "status"}
            aria-live="polite"
            aria-atomic="true"
        >
            {feedback.message
            or (
                "Request in progress…"
                    if feedback.status in ["loading", "running"]
                    else "Some results are unavailable. Review the errors below."
                        if feedback.status == "partial"
                        else "Operation completed."
                            if feedback.status == "completed"
                            else idle_message
            )}
        </div>;
}
