"""Service provider mode configuration and helper utilities."""
sv {
    import os;

    glob MODE_MOCK = "mock";
    glob MODE_REAL = "real";
    glob MODE_DOCKER = "docker";
    glob MODE_REMOTE = "remote";
    glob MODE_FIXTURE = "fixture";

    def get_service_mode -> str {
        return os.getenv("SYMPHONY_SERVICE_MODE", MODE_MOCK).strip().lower();
    }

    def is_real_mode -> bool {
        mode = get_service_mode();
        return mode in [MODE_REAL, MODE_DOCKER, MODE_REMOTE];
    }
}
