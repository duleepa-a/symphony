"""Bounded Gemini Investigator with evidence validation and safe failures."""

import os;
import from jaclang.byllm.lib {
    AuthenticationError,
    ConfigurationError,
    Model,
    ModelNotFoundError,
    ModelPool,
    OutputConversionError,
    RateLimitError,
}
import from contracts { InvestigationResult, OperationEnvelope, OperationError, }
import from .tools {
    check_service_health_tool,
    get_service_logs_tool,
    investigation_evidence,
    investigation_tool_timeline,
    prepare_diagnostic_run,
    trace_requests_tool,
}
import from .validation { investigation_result_to_dict, validate_investigation_result, }

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

def investigate_incident_impl(
    incident_context: str, active_run_id: str,
) -> InvestigationResult by investigator_model(
    tools=[check_service_health_tool, get_service_logs_tool, trace_requests_tool, ],
    temperature=0.2,
    max_tokens=900,
    max_react_iterations=6,
    max_output_retries=1,
);

sem investigate_incident_impl = "Investigate a simulated reliability incident using only diagnostic tools. Collect evidence before ranking causes. Never invent observations, hidden faults, or dependencies.";
sem investigate_incident_impl.incident_context = "Documented topology and user-visible service states only. It excludes the simulator's private graph and injected fault.";
sem investigate_incident_impl.active_run_id = "The current simulation run ID. Evidence from any other run is stale and must be ignored.";

def _investigator_failure(code: str, message: str) -> OperationEnvelope {
    return OperationEnvelope(
        status="failed", error=OperationError(code=code, message=message),
    );
}

def run_investigation_impl(
    incident_context: str, active_run_id: str,
) -> OperationEnvelope {
    prepare_diagnostic_run(active_run_id);
    try {
        model_result = investigate_incident_impl(incident_context, active_run_id);
        validated = validate_investigation_result(
            model_result,
            investigation_tool_timeline(),
            investigation_evidence(),
            active_run_id,
        );
        if validated.status != "completed" {
            return _investigator_failure(
                "investigator_insufficient_evidence", validated.explanation
            );
        }
        return OperationEnvelope(
            status="completed", data=investigation_result_to_dict(validated),
        );
    } except AuthenticationError as error {
        return _investigator_failure("investigator_authentication_error", str(error));
    } except RateLimitError as error {
        return _investigator_failure("investigator_rate_limit", str(error));
    } except ModelNotFoundError as error {
        return _investigator_failure("investigator_model_not_found", str(error));
    } except OutputConversionError as error {
        return _investigator_failure("investigator_malformed_output", str(error));
    } except ConfigurationError as error {
        return _investigator_failure("investigator_configuration_error", str(error));
    } except TimeoutError as error {
        return _investigator_failure("investigator_timeout", str(error));
    } except Exception as error {
        return _investigator_failure("investigator_tool_or_provider_error", str(error));
    }
}
