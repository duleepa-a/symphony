"""Service registry: decides which services exist in real mode.

Sources, chosen with SYMPHONY_DISCOVERY:
  static  the six-service demonstration catalog (default)
  file    a JSON file named by SYMPHONY_SERVICES_FILE
  docker  containers carrying symphony.* labels, read with the docker CLI

A failed refresh keeps the last good topology and reports the error. It never
substitutes the demonstration catalog for services that could not be found.
"""
sv {
    import json;
    import os;
    import re;
    import subprocess;
    import time;
    import from threading { RLock }
    import from contracts { Dependency, PackageInventoryItem, Service }
    import from integration.service_provider { is_real_mode }
    import from topology { reset_topology, set_topology, topology_source }

    glob DOCKER_SEPARATOR: str = "@@@",
         DEFAULT_REFRESH_SECONDS: float = 30.0,
         DOCKER_TIMEOUT_SECONDS: float = 10.0,
         DOCKER_FORMAT: str = (
             '{{.Label "symphony.id"}}@@@{{.Label "symphony.name"}}@@@{{.Label "symphony.url"}}@@@' + '{{.Label "symphony.port"}}@@@{{.Label "symphony.depends_on"}}@@@' + '{{.Label "symphony.packages"}}@@@{{.Ports}}'
         ),
         registry_lock = RLock();

    obj RegistryState {
        has last_refresh: float = 0.0,
            source: str = "catalog",
            error: str = "",
            problems: list[str] = [],
            service_count: int = 0,
            known_urls: dict[str, str] = {};
    }

    glob registry_state: RegistryState = RegistryState();

    def discovery_source -> str {
        value = os.getenv("SYMPHONY_DISCOVERY", "static").strip().lower();
        return value if value in ["static", "file", "docker"] else "static";
    }

    def refresh_seconds -> float {
        try {
            value = float(os.getenv("SYMPHONY_DISCOVERY_INTERVAL", "").strip());
        } except ValueError {
            return DEFAULT_REFRESH_SECONDS;
        }
        return value if value >= 1.0 else 1.0;
    }

    def normalize_id(raw: str) -> str {
        return re.sub(r"[^a-z0-9_]", "_", str(raw).strip().lower());
    }

    def valid_id(service_id: str) -> bool {
        return re.fullmatch(r"[a-z][a-z0-9_]{0,39}", service_id) is not None;
    }

    def title_of(service_id: str) -> str {
        return " ".join([word.capitalize() for word in service_id.split("_")]);
    }

    def parse_packages(raw: str) -> list[dict[str, str]] {
        # "PyPI:pyjwt@1.7.1,npm:@scope/pkg@2.0.0" -> one record per entry.
        found: list[dict[str, str]] = [];
        for entry in raw.split(",") {
            entry = entry.strip();
            if not entry or ":" not in entry or "@" not in entry[1:] {
                continue;
            }
            head = entry.partition(":");
            tail = str(head[2]).rpartition("@");
            ecosystem = str(head[0]).strip();
            name = str(tail[0]).strip();
            version = str(tail[2]).strip();
            if ecosystem and name and version {
                found.append(
                    {"ecosystem": ecosystem, "name": name, "version": version}
                );
            }
        }
        return found;
    }

    def parse_host_port(ports: str, container_port: str) -> str {
        # "0.0.0.0:8101->8000/tcp, :::8101->8000/tcp" -> "8101"
        for part in ports.split(",") {
            part = part.strip();
            if "->" not in part {
                continue;
            }
            sides = part.partition("->");
            target_port = str(sides[2]).split("/")[0];
            if container_port and target_port != container_port {
                continue;
            }
            host_port = str(sides[0]).rsplit(":", 1)[-1];
            if host_port.isdigit() {
                return host_port;
            }
        }
        return "";
    }

    def build_topology(raw_services: list[dict[str, any]]) -> dict[str, any] {
        # Validate raw records and return services, dependencies, urls and problems.
        services: list[Service] = [];
        urls: dict[str, str] = {};
        declared: dict[str, list[str]] = {};
        problems: list[str] = [];
        for raw in raw_services {
            service_id = normalize_id(raw.get("id", ""));
            if not valid_id(service_id) {
                problems.append(
                    f"Ignored a service with an invalid ID: {raw.get('id', '')!r}."
                );
                continue;
            }
            if service_id in declared {
                problems.append(f"Ignored a duplicate service ID: {service_id}.");
                continue;
            }
            inventory = [
                PackageInventoryItem(
                    name=item["name"],
                    ecosystem=item["ecosystem"],
                    version=item["version"]
                )
                for item in raw.get("packages", [])
                if item.get("name") and item.get("ecosystem") and item.get("version")
            ];
            services.append(
                Service(
                    id=service_id,
                    name=str(raw.get("name", "")).strip() or title_of(service_id),
                    inventory=inventory
                )
            );
            declared[service_id] = [
                normalize_id(item) for item in raw.get("depends_on", [])
            ];
            url = str(raw.get("url", "")).strip().rstrip("/");
            if url {
                urls[service_id] = url;
            }
        }
        dependencies: list[Dependency] = [];
        seen: set[tuple[str, str]] = set();
        for (source_id, targets) in declared.items() {
            for target_id in targets {
                if not target_id {
                    continue;
                }
                if target_id == source_id {
                    problems.append(f"Ignored {source_id} depending on itself.");
                } elif target_id not in declared {
                    problems.append(
                        f"{source_id} declares a dependency on {target_id}, which is not a known service."
                    );
                } elif (source_id, target_id) not in seen {
                    seen.add((source_id, target_id));
                    dependencies.append(
                        Dependency(source_id=source_id, target_id=target_id)
                    );
                }
            }
        }
        return {
            "services": services,
            "dependencies": dependencies,
            "urls": urls,
            "problems": problems
        };
    }

    def records_from_file(path: str) -> list[dict[str, any]] {
        with open(path, encoding="utf-8") as handle {
            document = json.load(handle);
        }
        items = document.get("services") if isinstance(document, dict) else None;
        if not isinstance(items, list) {
            raise ValueError("The services file must contain a 'services' list.");
        }
        return [
            {
                "id": item.get("id", ""),
                "name": item.get("name", ""),
                "url": item.get("url", ""),
                "depends_on": item.get("depends_on", []),
                "packages": item.get("packages", [])
            }
            for item in items
            if isinstance(item, dict)
        ];
    }

    def records_from_docker() -> list[dict[str, any]] {
        completed = subprocess.run(
            [
                "docker",
                "ps",
                "-a",
                "--filter",
                "label=symphony.id",
                "--format",
                DOCKER_FORMAT
            ],
            capture_output=True,
            text=True,
            timeout=DOCKER_TIMEOUT_SECONDS
        );
        if completed.returncode != 0 {
            raise RuntimeError(
                completed.stderr.strip() or "docker ps exited with an error."
            );
        }
        records: list[dict[str, any]] = [];
        for line in completed.stdout.splitlines() {
            fields = line.split(DOCKER_SEPARATOR);
            if len(fields) < 7 {
                continue;
            }
            service_id = normalize_id(fields[0]);
            url: str = str(fields[2]).strip();
            if not url {
                host_port = parse_host_port(fields[6], fields[3].strip());
                if host_port {
                    url = f"http://localhost:{host_port}";
                } else {
                    # A stopped container publishes no port; keep the last known address.
                    url = registry_state.known_urls.get(service_id, "");
                }
            }
            records.append(
                {
                    "id": fields[0],
                    "name": fields[1],
                    "url": url,
                    "depends_on": [
                        item.strip()
                        for item in fields[4].split(",")
                        if item.strip()
                    ],
                    "packages": parse_packages(fields[5])
                }
            );
        }
        return records;
    }

    def apply_topology(records: list[dict[str, any]], source: str) -> dict[str, any] {
        built = build_topology(records);
        set_topology(built["services"], built["dependencies"], built["urls"], source);
        registry_state.known_urls = {** registry_state.known_urls, ** built["urls"]};
        registry_state.problems = built["problems"];
        registry_state.service_count = len(built["services"]);
        return built;
    }

    def refresh_registry -> dict[str, any] {
        with registry_lock {
            source = discovery_source();
            registry_state.last_refresh = time.time();
            registry_state.source = source;
            registry_state.error = "";
            try {
                if source == "file" {
                    path = os.getenv("SYMPHONY_SERVICES_FILE", "").strip();
                    if not path {
                        raise ValueError("SYMPHONY_SERVICES_FILE is not set.");
                    }
                    apply_topology(records_from_file(path), "file");
                } elif source == "docker" {
                    apply_topology(records_from_docker(), "docker");
                } else {
                    reset_topology();
                    registry_state.problems = [];
                    registry_state.service_count = 6;
                }
            } except Exception as error {
                # Keep the last good topology; report why discovery failed.
                registry_state.error = f"{source} discovery failed: {error}";
                if topology_source() == "catalog" and source != "static" {
                    set_topology([], [], {}, source);
                    registry_state.service_count = 0;
                }
            }
            return registry_status();
        }
    }

    def registry_status -> dict[str, any] {
        with registry_lock {
            return {
                "source": registry_state.source,
                "services": registry_state.service_count,
                "error": registry_state.error,
                "problems": list(registry_state.problems)
            };
        }
    }

    def ensure_registry {
        # Refresh on first use and then at most once per interval.
        if not is_real_mode() {
            return;
        }
        with registry_lock {
            due = (
                registry_state.last_refresh == 0.0
                or time.time() - registry_state.last_refresh >= refresh_seconds()
            );
            if due {
                refresh_registry();
            }
        }
    }

    def reset_registry {
        with registry_lock {
            registry_state.last_refresh = 0.0;
            registry_state.source = "catalog";
            registry_state.error = "";
            registry_state.problems = [];
            registry_state.service_count = 0;
            registry_state.known_urls = {};
            reset_topology();
        }
    }
}
