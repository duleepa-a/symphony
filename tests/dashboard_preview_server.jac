"""Server-only fixture composition; loaded exclusively by the preview entry."""
import from integration.ports { configure_ports }
import from tests.dashboard_fixtures { fixture_ports, set_fixture_case }

with entry {
    configure_ports(fixture_ports());
}

def:pub fixture_mode(case_name: str) -> str {
    if case_name
        not in ["completed", "empty", "partial", "failed", "not_implemented", "slow"] {
        return "invalid";
    }
    configure_ports(fixture_ports());
    set_fixture_case(case_name);
    return case_name;
}
