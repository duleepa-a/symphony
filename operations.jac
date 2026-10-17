"""Stable public operation surface; feature implementations bind through integration/."""
import from contracts { DashboardState, OperationEnvelope, InvestigationResult }
import from integration.gateway { read_dashboard, invoke }
import from integration.ports { configure_ports }
import from integration.bindings { production_ports }
import from jaclang.byllm.lib { Model, ModelPool }
import os;

glob investigator_model = ModelPool(
         models=[
             Model(model_name=os.getenv("LLM_MODEL", "gemini/gemini-3.8-flash")),
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

with entry {
    configure_ports(production_ports());
}

def:pub get_dashboard_state -> DashboardState {
    return read_dashboard();
}

def:pub start_incident(incident_id: str) -> OperationEnvelope {
    return invoke("start_incident", {"incident_id": incident_id});
}

def:pub reset_incident -> OperationEnvelope {
    return invoke("reset_incident", {});
}

def:pub check_service_health(service_id: str) -> OperationEnvelope {
    return invoke("check_service_health", {"service_id": service_id});
}

def:pub get_service_logs(service_id: str) -> OperationEnvelope {
    return invoke("get_service_logs", {"service_id": service_id});
}

def:pub trace_requests(service_id: str) -> OperationEnvelope {
    return invoke("trace_requests", {"service_id": service_id});
}

def:pub run_investigation -> OperationEnvelope {
    return invoke("run_investigation", {});
}

def:pub scan_service_dependencies(service_id: str) -> OperationEnvelope {
    return invoke("scan_service_dependencies", {"service_id": service_id});
}

def:pub analyze_security_impact(service_id: str) -> OperationEnvelope {
    return invoke("analyze_security_impact", {"service_id": service_id});
}

def:pub preview_recovery(service_id: str) -> OperationEnvelope {
    return invoke("preview_recovery", {"service_id": service_id});
}

def investigate_incident(incident_context: str) -> InvestigationResult by investigator_model(
    tools=[check_service_health, get_service_logs, trace_requests],
    temperature=0.2,
    max_tokens=900,
    max_react_iterations=6,
    max_output_retries=1,
);

sem investigate_incident = "Investigate a simulated reliability incident using only the available diagnostic tools. Collect evidence before proposing causes. Never invent tool results or hidden relationships.";
sem investigate_incident.incident_context = "Documented topology and user-visible incident context. It never contains the private true graph or injected root fault.";


sem check_service_health = "Check the currently observable health of one simulated service. This tool never reveals the injected fault or private true graph.";
sem check_service_health.service_id = "Stable service ID: frontend, api_gateway, payment, catalog, auth, or database.";
sem get_service_logs = "Read deterministic diagnostic log observations for one simulated service. Treat unavailable diagnostics as unavailable, not healthy.";
sem get_service_logs.service_id = "Stable service ID whose diagnostic logs should be inspected.";
sem trace_requests = "Inspect runtime request-trace observations involving one simulated service. Only trace evidence may support a newly discovered dependency.";
sem trace_requests.service_id = "Stable service ID whose incoming and outgoing request traces should be inspected.";
