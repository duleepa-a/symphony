"""Deterministic OSV scanner tests; live network coverage is opt-in."""

import os;
import pytest;

def _fixture_empty_query(package: str, ecosystem: str, version: str) -> dict[str, any] {
    return {"vulns": []};
}

def _fixture_finding_query(
    package: str, ecosystem: str, version: str
) -> dict[str, any] {
    return {"vulns": [{"id": "GHSA-fixture-0001", "summary": "Fixture issue"}]};
}

def _fixture_complete_finding_query(
    package: str, ecosystem: str, version: str
) -> dict[str, any] {
    return {
        "vulns": [
            {
                "id": "GHSA-fixture-complete",
                "summary": "Complete query record",
                "database_specific": {"severity": "HIGH"},
                "references": [
                    {"type": "ADVISORY", "url": "https://example.invalid/complete"}
                ],

            }
        ]
    };
}

def _fixture_details(advisory_id: str) -> dict[str, any] {
    return {
        "id": advisory_id,
        "summary": "Detailed fixture advisory",
        "severity": [{"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L"}],
        "references": [
            {"type": "WEB", "url": "https://example.invalid/details"},
            {"type": "ADVISORY", "url": "https://example.invalid/advisory"},

        ],

    };
}

def _fixture_details_without_severity(advisory_id: str) -> dict[str, any] {
    return {
        "id": advisory_id,
        "summary": "Severity unavailable",
        "references": [{"type": "WEB", "url": "https://example.invalid/item"}],

    };
}

def _fixture_failed_details(advisory_id: str) -> dict[str, any] {
    raise RuntimeError("fixture details failure");
}

def _fixture_failed_query(
    package: str, ecosystem: str, version: str
) -> dict[str, any] {
    raise RuntimeError("fixture query failure");
}

def _fixture_timeout_query(
    package: str, ecosystem: str, version: str
) -> dict[str, any] {
    raise RuntimeError("OSV request timed out");
}

def _fixture_non_200_query(
    package: str, ecosystem: str, version: str
) -> dict[str, any] {
    raise RuntimeError("OSV HTTP 503");
}

def _fixture_malformed_query(
    package: str, ecosystem: str, version: str
) -> dict[str, any] {
    return {"vulns": "not-a-list"};
}

def _fixture_mixed_query(package: str, ecosystem: str, version: str) -> dict[str, any] {
    if package == "broken" {
        raise RuntimeError("fixture package failure");
    }
    return {"vulns": []};
}

test "completed no-findings is distinct from failure" {
    inventory = [PackageInventoryItem(name="safe", ecosystem="npm", version="1.0.0")];
    result = scan_inventory_with_transport(
        "fixture", inventory, _fixture_empty_query, _fixture_details
    );
    assert result.status == "completed";
    assert result.data["finding_count"] == 0;
    assert result.data["packages"][0]["status"] == "completed";
    assert result.error is None;
}

test "normalizes advisory details and preferred reference" {
    item = PackageInventoryItem(name="affected", ecosystem="PyPI", version="2.0.0");
    result = scan_package_with_transport(
        item, _fixture_finding_query, _fixture_details
    );
    finding = result.findings[0];
    assert result.status == "completed";
    assert finding.advisory_id == "GHSA-fixture-0001";
    assert finding.severity.startswith("CVSS_V3:");
    assert finding.reference_url == "https://example.invalid/advisory";
    assert finding.package == "affected";
}

test "does not fetch details when query record is complete" {
    item = PackageInventoryItem(name="affected", ecosystem="npm", version="2.0.0");
    result = scan_package_with_transport(
        item, _fixture_complete_finding_query, _fixture_failed_details
    );
    assert result.status == "completed";
    assert result.findings[0].severity == "HIGH";
    assert result.findings[0].reference_url == "https://example.invalid/complete";
}

test "preserves unknown severity" {
    item = PackageInventoryItem(name="affected", ecosystem="npm", version="3.0.0");
    result = scan_package_with_transport(
        item, _fixture_finding_query, _fixture_details_without_severity
    );
    assert result.status == "completed";
    assert result.findings[0].severity == "unknown";
}

test "detail failure is partial and retains query finding" {
    item = PackageInventoryItem(name="affected", ecosystem="npm", version="3.0.0");
    result = scan_package_with_transport(
        item, _fixture_finding_query, _fixture_failed_details
    );
    assert result.status == "partial";
    assert len(result.findings) == 1;
    assert result.findings[0].advisory_id == "GHSA-fixture-0001";
    assert "details failure" in result.error;
}

test "mixed package outcomes produce partial scan" {
    inventory = [
        PackageInventoryItem(name="safe", ecosystem="npm", version="1.0.0"),
        PackageInventoryItem(name="broken", ecosystem="npm", version="1.0.0"),

    ];
    result = scan_inventory_with_transport(
        "fixture", inventory, _fixture_mixed_query, _fixture_details
    );
    assert result.status == "partial";
    assert len(result.data["packages"]) == 2;
    assert result.error is not None;
    assert result.error.code == "osv_scan_partial";
}

test "complete transport failure never reports zero findings" {
    inventory = [PackageInventoryItem(name="broken", ecosystem="npm", version="1.0.0")];
    result = scan_inventory_with_transport(
        "fixture", inventory, _fixture_failed_query, _fixture_details
    );
    assert result.status == "failed";
    assert result.error is not None;
    assert result.error.code == "osv_scan_failed";
    assert result.data["packages"][0]["status"] == "failed";
}

test "malformed query payload is a failed package" {
    item = PackageInventoryItem(name="broken", ecosystem="npm", version="1.0.0");
    result = scan_package_with_transport(
        item, _fixture_malformed_query, _fixture_details
    );
    assert result.status == "failed";
    assert "must be a list" in result.error;
}

test "malformed JSON response is rejected" {
    with pytest.raises(ValueError, match="malformed JSON") {
        _decode_json_object(b"not-json");
    }
}

test "timeout remains a failed package" {
    item = PackageInventoryItem(name="slow", ecosystem="npm", version="1.0.0");
    result = scan_package_with_transport(
        item, _fixture_timeout_query, _fixture_details
    );
    assert result.status == "failed";
    assert "timed out" in result.error;
}

test "non-200 remains a failed package" {
    item = PackageInventoryItem(name="unavailable", ecosystem="npm", version="1.0.0");
    result = scan_package_with_transport(
        item, _fixture_non_200_query, _fixture_details
    );
    assert result.status == "failed";
    assert "HTTP 503" in result.error;
}

test "unknown service is rejected" {
    result = scan_service_dependencies_impl("not-a-service");
    assert result.status == "failed";
    assert result.error is not None;
    assert result.error.code == "unknown_service";
}

test "real OSV lookup is available when explicitly enabled" {
    if os.getenv("RUN_LIVE_OSV_TESTS", "") != "1" {
        pytest.skip("set RUN_LIVE_OSV_TESTS=1 to call api.osv.dev");
    }
    result = scan_service_dependencies_impl("catalog");
    assert result.status in ["completed", "partial"];
    assert len(result.data["packages"]) == 1;
    assert result.data["packages"][0]["package"] == "lodash";
}
