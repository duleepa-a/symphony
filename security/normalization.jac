"""Normalize OSV payloads into stable, JSON-compatible scan records."""

import from contracts { PackageInventoryItem }

obj OsvFinding {
    has advisory_id: str,
        summary: str,
        package: str,
        ecosystem: str,
        version: str,
        severity: str = "unknown",
        reference_url: str = "";
}

obj PackageScanResult {
    has package: str,
        ecosystem: str,
        version: str,
        status: str,
        findings: list[OsvFinding] = [],
        error: str = "";
}

def _string_value(value: any, fallback: str = "") -> str {
    if value is None {
        return fallback;
    }
    text = str(value).strip();
    return text if text else fallback;
}

def _severity_from(payload: dict[str, any]) -> str {
    database_specific = payload.get("database_specific", {});
    if isinstance(database_specific, dict) {
        value = _string_value(database_specific.get("severity"));
        if value {
            return value;
        }
    }

    ecosystem_specific = payload.get("ecosystem_specific", {});
    if isinstance(ecosystem_specific, dict) {
        value = _string_value(ecosystem_specific.get("severity"));
        if value {
            return value;
        }
    }

    severities = payload.get("severity", []);
    if isinstance(severities, list) and len(severities) > 0 {
        first = severities[0];
        if isinstance(first, dict) {
            score = _string_value(first.get("score"));
            severity_type = _string_value(first.get("type"));
            if score and severity_type {
                return f"{severity_type}: {score}";
            }
            if score {
                return score;
            }
        }
    }
    return "unknown";
}

def _reference_from(payload: dict[str, any]) -> str {
    references = payload.get("references", []);
    if not isinstance(references, list) {
        return "";
    }
    fallback = "";
    for reference in references {
        if not isinstance(reference, dict) {
            continue;
        }
        url = _string_value(reference.get("url"));
        if not url {
            continue;
        }
        if _string_value(reference.get("type")).upper() == "ADVISORY" {
            return url;
        }
        if not fallback {
            fallback = url;
        }
    }
    return fallback;
}

def needs_advisory_details(payload: dict[str, any]) -> bool {
    return (
        not _string_value(payload.get("summary"))
        or _severity_from(payload) == "unknown"
        or not _reference_from(payload)
    );
}

def normalize_finding(
    query_payload: dict[str, any],
    details_payload: dict[str, any],
    item: PackageInventoryItem,
) -> OsvFinding {
    advisory_id = _string_value(
        details_payload.get("id"), _string_value(query_payload.get("id"), "unknown")
    );
    summary = _string_value(
        details_payload.get("summary"), _string_value(query_payload.get("summary"))
    );
    if not summary {
        summary = "No summary provided by OSV";
    }
    severity = _severity_from(details_payload);
    if severity == "unknown" {
        severity = _severity_from(query_payload);
    }
    reference_url = _reference_from(details_payload);
    if not reference_url {
        reference_url = _reference_from(query_payload);
    }
    return OsvFinding(
        advisory_id=advisory_id,
        summary=summary,
        severity=severity,
        reference_url=reference_url,
        package=item.name,
        ecosystem=item.ecosystem,
        version=item.version,
    );
}

def finding_to_dict(finding: OsvFinding) -> dict[str, any] {
    return {
        "advisory_id": finding.advisory_id,
        "summary": finding.summary,
        "severity": finding.severity,
        "reference_url": finding.reference_url,
        "package": finding.package,
        "ecosystem": finding.ecosystem,
        "version": finding.version,

    };
}

def package_result_to_dict(result: PackageScanResult) -> dict[str, any] {
    return {
        "package": result.package,
        "ecosystem": result.ecosystem,
        "version": result.version,
        "status": result.status,
        "findings": [finding_to_dict(item) for item in result.findings],
        "error": result.error,

    };
}
