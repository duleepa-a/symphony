"""Reusable, explicit empty-state content."""
def:pub EmptyState(title: str, description: str) -> JsxElement {
    <div className="empty-result">
        <strong>{title}</strong>
        <p>{description}</p>
    </div>
}
