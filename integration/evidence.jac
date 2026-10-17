"""Shared trace matching for native simulator spans and flat handoff evidence."""
sv {
    import from contracts { Evidence, Dependency }
    def trace_supports(item: Evidence, source: str, target: str, run_id: str) -> bool {
        if item.tool != "trace_requests" or item.simulation_run_id != run_id {
            return False;
        }
        observation = item.observation;
        if observation.get("source_id") == source
        and observation.get("target_id") == target {
            return True;
        }
        for span in observation.get("spans", []) {
            if span.get("outcome") not in ["ok", "timeout", "error_503"] {
                continue;
            }
            if item.service_id == source
            and span.get("direction") == "outgoing"
            and span.get("peer") == target {
                return True;
            }
            if item.service_id == target
            and span.get("direction") == "incoming"
            and span.get("peer") == source {
                return True;
            }
        }
        return False;
    }
    def supports_dependency(
        dependency: Dependency, evidence: list[Evidence], run_id: str
    ) -> bool {
        if not dependency.evidence_ids
        or dependency.source_id == dependency.target_id {
            return False;
        }
        for evidence_id in dependency.evidence_ids {
            if not `any(
                item.id == evidence_id
                and trace_supports(
                    item, dependency.source_id, dependency.target_id, run_id
                ) for item in evidence
            ) {
                return False;
            }
        }
        return True;
    }
}
