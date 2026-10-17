"""Process-local run-scoped result repository with revision-checked writes."""
sv {
    import from copy { deepcopy }
    import from threading { RLock }
    import from contracts { OperationEnvelope }
    obj ResultStore {
        has run_id: str = "",
            revisions: dict[str, int] = {},
            results: dict[str, OperationEnvelope] = {};

        def sync(run_id: str) {
            if self.run_id != run_id {
                self.run_id = run_id;
                self.revisions = {};
                self.results = {};
            }
        }

        def key(operation: str, service_id: str = "") -> str {
            return operation + ":" + service_id;
        }

        def begin(operation: str, service_id: str, run_id: str) -> int {
            self.sync(run_id);
            key = self.key(operation, service_id);
            revision = self.revisions.get(key, 0) + 1;
            self.revisions[key] = revision;
            self.results.pop(key, None);
            if operation == "scan_service_dependencies" {
                self.results.pop(self.key("run_security_analysis", service_id), None);
            }
            if operation == "run_investigation" {
                self.results.pop(self.key("run_recovery_agent"), None);
            }
            return revision;
        }

        def revision(operation: str, service_id: str = "") -> int {
            return self.revisions.get(self.key(operation, service_id), 0);
        }

        def latest(operation: str, service_id: str = "") -> OperationEnvelope | None {
            return deepcopy(self.results.get(self.key(operation, service_id)));
        }

        def commit(
            operation: str,
            service_id: str,
            run_id: str,
            revision: int,
            result: OperationEnvelope
        ) -> bool {
            if self.run_id != run_id
            or self.revision(operation, service_id) != revision {
                return False;
            }
            self.results[self.key(operation, service_id)] = deepcopy(result);
            return True;
        }
    }
    glob result_store = ResultStore(),
         result_lock = RLock();
}
