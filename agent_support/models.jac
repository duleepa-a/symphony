"""Shared Gemini model pool and error mapping for the Recovery and Security agents."""

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
import from contracts { OperationEnvelope, OperationError }

def make_agent_model -> ModelPool {
    return ModelPool(
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
}

def agent_failure(code: str, message: str) -> OperationEnvelope {
    return OperationEnvelope(
        status="failed", error=OperationError(code=code, message=message),
    );
}

def envelope_for_model_error(prefix: str, error: Exception) -> OperationEnvelope {
    # Every provider, quota, timeout, output, and tool error becomes an explicit failure.
    if isinstance(error, AuthenticationError) {
        return agent_failure(f"{prefix}_authentication_error", str(error));
    }
    if isinstance(error, RateLimitError) {
        return agent_failure(f"{prefix}_rate_limit", str(error));
    }
    if isinstance(error, ModelNotFoundError) {
        return agent_failure(f"{prefix}_model_not_found", str(error));
    }
    if isinstance(error, OutputConversionError) {
        return agent_failure(f"{prefix}_malformed_output", str(error));
    }
    if isinstance(error, ConfigurationError) {
        return agent_failure(f"{prefix}_configuration_error", str(error));
    }
    if isinstance(error, TimeoutError) {
        return agent_failure(f"{prefix}_timeout", str(error));
    }
    return agent_failure(f"{prefix}_tool_or_provider_error", str(error));
}
