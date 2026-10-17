"""Public integration surface for the three parallel workstreams.

Only dashboard state is implemented in the foundation phase. Every unfinished
operation returns an explicit status and error instead of fake success data.
"""

import from contracts {
    DashboardState,
    OperationEnvelope,
    OperationError,
    InvestigationResult,
}
import from catalog { initial_dashboard_state }
import from jaclang.byllm.lib { Model, ModelPool }
import os;

glob investigator_model = ModelPool(
    models=[
        Model(
            model_name=os.getenv(
                "LLM_MODEL", "gemini/gemini-3.8-flash"
            )
        ),
        Model(
            model_name=os.getenv(
                "LLM_FALLBACK_MODEL", "gemini/gemini-3.1-flash-lite"
            )
        ),
    ],
    strategy="fallback",
    num_retries=1,
    timeout=45.0,
);

def not_implemented(operation: str, message: str) -> OperationEnvelope {
    return OperationEnvelope(
        status="not_implemented", error=OperationError(code=operation, message=message)
    );
}

def:pub get_dashboard_state -> DashboardState {
    return initial_dashboard_state();
}

def:pub start_incident(incident_id: str) -> OperationEnvelope {
    return not_implemented(
        "simulation_not_connected",
        f"Incident '{incident_id}' is defined but the simulator is not connected yet."
    );
}

def:pub reset_incident -> OperationEnvelope {
    return not_implemented(
        "simulation_not_connected",
        "Reset is available after the deterministic simulator is connected."
    );
}

def:pub check_service_health(service_id: str) -> OperationEnvelope {
    return not_implemented(
        "diagnostics_not_connected",
        f"Health diagnostics for '{service_id}' are not connected yet."
    );
}

sem check_service_health = "Check the currently observable health of one simulated service. This tool never reveals the injected fault or private true graph.";
sem check_service_health.service_id = "Stable service ID: frontend, api_gateway, payment, catalog, auth, or database.";

def:pub get_service_logs(service_id: str) -> OperationEnvelope {
    return not_implemented(
        "diagnostics_not_connected",
        f"Diagnostic logs for '{service_id}' are not connected yet."
    );
}

sem get_service_logs = "Read deterministic diagnostic log observations for one simulated service. Treat unavailable diagnostics as unavailable, not healthy.";
sem get_service_logs.service_id = "Stable service ID whose diagnostic logs should be inspected.";

def:pub trace_requests(service_id: str) -> OperationEnvelope {
    return not_implemented(
        "diagnostics_not_connected",
        f"Request traces for '{service_id}' are not connected yet."
    );
}

sem trace_requests = "Inspect runtime request-trace observations involving one simulated service. Only trace evidence may support a newly discovered dependency.";
sem trace_requests.service_id = "Stable service ID whose incoming and outgoing request traces should be inspected.";

def investigate_incident(incident_context: str) -> InvestigationResult by investigator_model(
    tools=[check_service_health, get_service_logs, trace_requests],
    temperature=0.2,
    max_tokens=900,
    max_react_iterations=6,
    max_output_retries=1,
);

sem investigate_incident = "Investigate a simulated reliability incident using only the available diagnostic tools. Collect evidence before proposing causes. Never invent tool results or hidden relationships.";
sem investigate_incident.incident_context = "Documented topology and user-visible incident context. It never contains the private true graph or injected root fault.";

def:pub run_investigation -> OperationEnvelope {
    context = "Six documented services are Frontend, API Gateway, Payment, Catalog, Auth, and Database. Documented dependencies: Frontend to API Gateway; API Gateway to Payment and Catalog; Payment and Catalog to Database. Investigate the current observable incident using tools.";
    try {
        result = investigate_incident(context);
        return OperationEnvelope(
            status=result.status,
            data={
                "tool_timeline": result.tool_timeline,
                "observed_evidence": result.observed_evidence,
                "candidate_root_causes": result.candidate_root_causes,
                "discovered_dependencies": result.discovered_dependencies,
                "explanation": result.explanation,

            },
        );
    } except Exception as error {
        return OperationEnvelope(
            status="failed",
            error=OperationError(
                code="investigator_model_error",
                message=f"The Investigator could not call the configured model: {error}",
            ),
        );
    }
}

def:pub scan_service_dependencies(service_id: str) -> OperationEnvelope {
    return not_implemented(
        "osv_not_connected",
        f"The real OSV lookup for '{service_id}' is not connected yet."
    );
}

def:pub analyze_security_impact(service_id: str) -> OperationEnvelope {
    return not_implemented(
        "impact_analysis_not_connected",
        f"Graph impact analysis for '{service_id}' is not connected yet."
    );
}

def:pub preview_recovery(service_id: str) -> OperationEnvelope {
    return not_implemented(
        "recovery_not_connected",
        f"Recovery verification for '{service_id}' is not connected yet."
    );
}
