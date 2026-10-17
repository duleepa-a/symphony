"""Run-scoped, read-only tool boundary for the Security Analyst agent.

The session record is private to this agent; it never touches the Investigator's
or the Recovery agent's state. Tools expose the current scan, graph impact, and
known dependencies. They never run a new OSV request.
"""

import from contracts { AssessedFinding }
import from simulation.impact { sim_analyze_impact }
import from simulation.state { sim_dashboard_state, sim_is_current_run }

obj SecurityJudgment {
    has findings: list[AssessedFinding] = [],
        priority: str = "low",
        explanation: str = "";
}

sem SecurityJudgment = "The analyst's risk judgment for one scanned service, based only on the scan results and graph impact it read through tools.";
sem SecurityJudgment.findings = "One entry per advisory worth reporting. Each must name an advisory ID and package that appear in the scan results.";
sem SecurityJudgment.priority = "low, medium, or high. Weigh advisory severity and how many services depend on the scanned service.";
sem SecurityJudgment.explanation = "Concise and cautious. Dependent services are potentially affected through the dependency chain, never called vulnerable or compromised without direct evidence. State what the scan could not cover.";

obj SecuritySession {
    has run_id: str = "",
        service_id: str = "",
        scan: dict[str, any] = {},
        tool_timeline: list[str] = [];
}

glob session: SecuritySession = SecuritySession();

def begin_security_session(run_id: str, service_id: str, scan: dict[str, any]) {
    session.run_id = run_id;
    session.service_id = service_id;
    session.scan = scan;
    session.tool_timeline = [];
}

def security_tool_timeline -> list[str] {
    return session.tool_timeline.copy();
}

def _record(label: str) {
    if not sim_is_current_run(session.run_id) {
        raise RuntimeError("Simulation changed during security analysis.");
    }
    session.tool_timeline.append(label);
}

def advisories_in(scan: dict[str, any]) -> list[dict[str, any]] {
    # Flatten package results; accept both the scanner and the dashboard field names.
    found: list[dict[str, any]] = [];
    for package in scan.get("packages", []) {
        name = package.get("package", package.get("name", ""));
        for item in package.get("findings", package.get("advisories", [])) {
            found.append(
                {
                    "advisory_id": item.get("advisory_id", item.get("id", "")),
                    "summary": item.get("summary", ""),
                    "severity": item.get("severity", "unknown"),
                    "reference_url": item.get("reference_url", ""),
                    "package": item.get("package", name),
                    "ecosystem": package.get("ecosystem", ""),
                    "version": package.get("version", ""),

                }
            );
        }
    }
    return found;
}

def get_scan_results_tool -> dict[str, any] {
    _record("get_scan_results()");
    scan = session.scan;
    return {
        "service_id": scan.get("service_id", session.service_id),
        "finding_count": scan.get("finding_count", 0),
        "packages": [
            {
                "package": package.get("package", package.get("name", "")),
                "ecosystem": package.get("ecosystem", ""),
                "version": package.get("version", ""),
                "status": package.get("status", "unknown"),
                "error": package.get("error", ""),

            } for package in scan.get("packages", [])
        ],
        "advisories": advisories_in(scan),

    };
}

sem get_scan_results_tool = "Read the current OSV scan of the selected service: per-package status and every advisory with its ID, package, summary, and severity. Unknown severity means OSV gave none.";

def get_impact_tool(service_id: str) -> dict[str, any] {
    _record(f"get_impact({service_id})");
    result = sim_analyze_impact(service_id);
    if result.status != "completed" {
        return {"error": {"code": result.error.code, "message": result.error.message}};
    }
    return {
        "service_id": service_id,
        "dependent_services": result.data["dependent_services"],
        "potential_exposure": result.data["potential_exposure"],
        "rule_based_priority": result.data["priority"],

    };
}

sem get_impact_tool = "Show which services depend on one service through known dependencies, with cautious exposure wording and the rule-based priority.";
sem get_impact_tool.service_id = "Stable service ID to inspect.";

def get_known_dependencies_tool -> dict[str, any] {
    _record("get_known_dependencies()");
    return {
        "dependencies": [
            {
                "source_id": link.source_id,
                "target_id": link.target_id,
                "kind": link.kind,

            } for link in sim_dashboard_state().dependencies
        ]
    };
}

sem get_known_dependencies_tool = "List documented and evidence-backed discovered dependencies. A source depends on its target.";
