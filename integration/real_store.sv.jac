"""Run identity and bounded evidence store for real-service mode.

Real mode never touches the simulator's state. The run ID changes only when the
observed service states change, so work done against an earlier picture of the
system is rejected as stale. Evidence is kept for the current run only, within a
fixed retention window.
"""
sv {
    import os;
    import from threading { RLock }
    import from contracts { Evidence }

    glob DEFAULT_EVIDENCE_LIMIT: int = 500,
         MIN_EVIDENCE_LIMIT: int = 10;

    def evidence_limit -> int {
        raw = os.getenv("SYMPHONY_EVIDENCE_LIMIT", "").strip();
        try {
            value = int(raw);
        } except ValueError {
            return DEFAULT_EVIDENCE_LIMIT;
        }
        return value if value >= MIN_EVIDENCE_LIMIT else MIN_EVIDENCE_LIMIT;
    }

    obj RealRuntime {
        has run_counter: int = 1,
            run_id: str = "real-1",
            signature: str = "",
            evidence_counter: int = 0,
            evidence_log: dict[str, Evidence] = {};
    }

    glob real_runtime: RealRuntime = RealRuntime(),
         real_lock = RLock();

    def states_signature(states: dict[str, str]) -> str {
        return "|".join([f"{key}:{states[key]}" for key in sorted(states.keys())]);
    }

    def current_real_run_id -> str {
        with real_lock {
            return real_runtime.run_id;
        }
    }

    def observe_real_states(states: dict[str, str]) -> str {
        # The first observation adopts the baseline; later changes start a new run.
        signature = states_signature(states);
        with real_lock {
            if real_runtime.signature == "" {
                real_runtime.signature = signature;
            } elif signature != real_runtime.signature {
                real_runtime.run_counter += 1;
                real_runtime.run_id = f"real-{real_runtime.run_counter}";
                real_runtime.signature = signature;
                real_runtime.evidence_counter = 0;
                real_runtime.evidence_log = {};
            }
            return real_runtime.run_id;
        }
    }

    def issue_real_evidence_record(
        tool: str, service_id: str, observation: dict[str, any]
    ) -> Evidence {
        with real_lock {
            real_runtime.evidence_counter += 1;
            evidence = Evidence(
                id=f"{real_runtime.run_id}-ev-{real_runtime.evidence_counter}",
                tool=tool,
                service_id=service_id,
                observation=observation,
                simulation_run_id=real_runtime.run_id
            );
            real_runtime.evidence_log[evidence.id] = evidence;
            limit = evidence_limit();
            while len(real_runtime.evidence_log) > limit {
                oldest = next(iter(real_runtime.evidence_log));
                real_runtime.evidence_log.pop(oldest);
            }
            return evidence;
        }
    }

    def lookup_real_evidence(evidence_id: str) -> Evidence | None {
        with real_lock {
            return real_runtime.evidence_log.get(evidence_id);
        }
    }

    def reset_real_runtime {
        with real_lock {
            real_runtime.run_counter = 1;
            real_runtime.run_id = "real-1";
            real_runtime.signature = "";
            real_runtime.evidence_counter = 0;
            real_runtime.evidence_log = {};
        }
    }
}
