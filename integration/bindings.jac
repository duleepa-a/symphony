"""Composition root. Add explicit feature imports here at the integration checkpoint.

Members 1 and 2 have not supplied modules in this branch. Bind their typed
exports here after handoff rather than importing optional modules dynamically.
The application's public operation names and frontend stay unchanged.
"""
import from integration.ports { FeaturePorts }

def production_ports() -> FeaturePorts {
    return FeaturePorts();
}
