"""Explicit agent handoff protocol. Each invocation receives a fresh session."""
sv {
    import from copy { deepcopy }
    import from contracts { OperationEnvelope, Dependency }
    def graph_key(links: list[Dependency]) -> str {
        return str(
            sorted((link.source_id, link.target_id, link.kind) for link in links)
        );
    }
    obj AgentSession {
        has simulation_run_id: str,
            service_id: str = "",
            facts: dict[str, any] = {},
            tool_timeline: list[str] = [];

        def read(name: str) -> any {
            if name not in self.facts {
                raise ValueError("Unknown read-only agent tool.");
            }
            self.tool_timeline.append(name);
            return deepcopy(self.facts[name]);
        }
    }
    obj AgentPorts {
        has security: Callable[[AgentSession], OperationEnvelope] | None = None,
            recovery: Callable[[AgentSession], OperationEnvelope] | None = None,
            repair_options: Callable[[], list[str]] | None = None,
            preview: Callable[[str, str], OperationEnvelope] | None = None;
    }
}
