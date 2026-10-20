"""Real server-side OSV.dev scanning with injectable transports for tests."""

import json;
import urllib.error;
import urllib.parse;
import urllib.request;
import from contracts { OperationEnvelope, OperationError, PackageInventoryItem, }
import from topology { topology_services }
import from .normalization {
    OsvFinding,
    PackageScanResult,
    needs_advisory_details,
    normalize_finding,
    package_result_to_dict,
}

glob OSV_API_BASE = "https://api.osv.dev/v1";
glob OSV_TIMEOUT_SECONDS = 8.0;

def _decode_json_object(body: bytes) -> dict[str, any] {
    try {
        payload = json.loads(body.decode("utf-8"));
    } except Exception as error {
        raise ValueError(f"OSV returned malformed JSON: {error}");
    }
    if not isinstance(payload, dict) {
        raise ValueError("OSV returned a non-object JSON payload");
    }
    return payload;
}

def _request_json(
    request: any, timeout: float = OSV_TIMEOUT_SECONDS
) -> dict[str, any] {
    try {
        response = urllib.request.urlopen(request, timeout=timeout);
        try {
            status = response.getcode();
            body = response.read();
        } finally {
            response.close();
        }
    } except urllib.error.HTTPError as error {
        raise RuntimeError(f"OSV HTTP {error.code}");
    } except urllib.error.URLError as error {
        raise RuntimeError(f"OSV network error: {error.reason}");
    } except TimeoutError {
        raise RuntimeError("OSV request timed out");
    }
    if status < 200 or status >= 300 {
        raise RuntimeError(f"OSV HTTP {status}");
    }
    return _decode_json_object(body);
}

def query_osv(package: str, ecosystem: str, version: str,) -> dict[str, any] {
    body = json.dumps(
        {"package": {"name": package, "ecosystem": ecosystem}, "version": version,}
    ).encode(
        "utf-8"
    );
    request = urllib.request.Request(
        f"{OSV_API_BASE}/query",
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    );
    return _request_json(request);
}

def get_osv_advisory(advisory_id: str) -> dict[str, any] {
    safe_id = urllib.parse.quote(advisory_id, safe="");
    request = urllib.request.Request(
        f"{OSV_API_BASE}/vulns/{safe_id}",
        headers={"Accept": "application/json"},
        method="GET",
    );
    return _request_json(request);
}

def inventory_for_service(service_id: str) -> list[PackageInventoryItem] | None {
    for service in topology_services() {
        if service.id == service_id {
            return service.inventory;
        }
    }
    return None;
}

def scan_package_with_transport(
    item: PackageInventoryItem,
    query_call: Callable[[str, str, str], dict[str, any]],
    details_call: Callable[[str], dict[str, any]],
) -> PackageScanResult {
    try {
        response = query_call(item.name, item.ecosystem, item.version);
        vulnerabilities = response.get("vulns", []);
        if vulnerabilities is None {
            vulnerabilities = [];
        }
        if not isinstance(vulnerabilities, list) {
            raise ValueError("OSV query field 'vulns' must be a list");
        }
    } except Exception as error {
        return PackageScanResult(
            package=item.name,
            ecosystem=item.ecosystem,
            version=item.version,
            status="failed",
            error=str(error),
        );
    }

    findings: list[OsvFinding] = [];
    detail_errors: list[str] = [];
    for vulnerability in vulnerabilities {
        if not isinstance(vulnerability, dict) {
            detail_errors.append("OSV query contained a malformed vulnerability entry");
            continue;
        }
        details: dict[str, any] = {};
        if needs_advisory_details(vulnerability) {
            advisory_id = str(vulnerability.get("id", "")).strip();
            if advisory_id {
                try {
                    details = details_call(advisory_id);
                } except Exception as error {
                    detail_errors.append(f"{advisory_id}: {error}");
                }
            } else {
                detail_errors.append("OSV vulnerability was missing an advisory ID");
            }
        }
        findings.append(normalize_finding(vulnerability, details, item));
    }

    return PackageScanResult(
        package=item.name,
        ecosystem=item.ecosystem,
        version=item.version,
        status="partial" if detail_errors else "completed",
        findings=findings,
        error="; ".join(detail_errors),
    );
}

def scan_inventory_with_transport(
    service_id: str,
    inventory: list[PackageInventoryItem],
    query_call: Callable[[str, str, str], dict[str, any]],
    details_call: Callable[[str], dict[str, any]],
) -> OperationEnvelope {
    packages = [
        scan_package_with_transport(item, query_call, details_call)
        for item in inventory
    ];
    completed_count = len(
        [
            item
            for item in packages
            if item.status == "completed"
        ]
    );
    failed_count = len(
        [
            item
            for item in packages
            if item.status == "failed"
        ]
    );
    finding_count = sum([len(item.findings) for item in packages]);

    status = "completed";
    error: OperationError | None = None;
    if packages and failed_count == len(packages) {
        status = "failed";
        error = OperationError(
            code="osv_scan_failed",
            message="Every package lookup failed; no zero-findings claim was made.",
        );
    } elif completed_count != len(packages) {
        status = "partial";
        error = OperationError(
            code="osv_scan_partial",
            message="Some advisory data could not be retrieved or normalized.",
        );
    }

    return OperationEnvelope(
        status=status,
        data={
            "service_id": service_id,
            "inventory": [
                {
                    "name": item.name,
                    "ecosystem": item.ecosystem,
                    "version": item.version,

                } for item in inventory
            ],
            "packages": [package_result_to_dict(item) for item in packages],
            "finding_count": finding_count,

        },
        error=error,
    );
}

def scan_service_dependencies_impl(service_id: str) -> OperationEnvelope {
    inventory = inventory_for_service(service_id);
    if inventory is None {
        return OperationEnvelope(
            status="failed",
            error=OperationError(
                code="unknown_service", message=f"Unknown service ID: {service_id}",
            ),
        );
    }
    if len(inventory) == 0 {
        return OperationEnvelope(
            status="failed",
            error=OperationError(
                code="inventory_unavailable",
                message="No package inventory is known for this service, so nothing was scanned. This is not a clean result.",
            ),
        );
    }
    return scan_inventory_with_transport(
        service_id, inventory, query_osv, get_osv_advisory,
    );
}
