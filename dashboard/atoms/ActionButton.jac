"""Accessible action primitive with consistent busy behavior."""
def:pub ActionButton(
    label: str,
    on_click: Callable[[], None],
    disabled: bool = False,
    busy: bool = False,
    tone: str = "primary"
) -> JsxElement {
    <button
        type="button"
        className={f"button {tone}"}
        disabled={disabled or busy}
        aria-busy={busy}
        onClick={on_click}
    >
        {"Working…" if busy else label}
    </button>
}
