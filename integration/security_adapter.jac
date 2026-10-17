"""Translate scanner handoff fields into the dashboard's package/advisory view."""
sv {
    import from contracts { OperationEnvelope }
    import from security.osv { scan_service_dependencies_impl }
    def normalize_scan(result: OperationEnvelope) -> OperationEnvelope {
        for package in result.data.get("packages", []) {
            package["name"] = package.get("package", "");
            package["advisories"] = [
                {** finding, "id": finding.get("advisory_id", "unknown")}
                for finding in package.get("findings", [])
            ];
            message = package.get("error", "");
            package["error"] = {"message": message} if message else None;
        }
        return result;
    }
    def scan(service_id: str) -> OperationEnvelope {
        return normalize_scan(scan_service_dependencies_impl(service_id));
    }
}
