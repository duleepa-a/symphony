# Service contract

This is what a service must expose for SYMPHONY to observe it in real mode (`SYMPHONY_SERVICE_MODE=real`). SYMPHONY only reads. It never calls an endpoint that changes a service.

Each service is reached at `SERVICE_<ID>_URL`, which defaults to `http://localhost:<port>`. IDs and default ports are `frontend` 8100, `auth` 8101, `payment` 8102, `catalog` 8103, `api_gateway` 8104 and `database` 8105. Every request carries an `X-Simulation-Run-Id` header with SYMPHONY's current run ID. Services may log it and must not depend on it.

Requests time out after 3 seconds. A timeout, a refused connection or any other transport error is treated as the service being down.

## `GET /health`

```json
{ "state": "healthy | degraded | down", "message": "optional human-readable text" }
```

- HTTP 200 with `healthy` or `degraded`. HTTP 503 with `down` is recommended.
- Any HTTP status of 400 or above counts as `down`, whatever the body says.
- A missing or unknown `state` on a 2xx response counts as `healthy`, so always send it.
- `degraded` means the service answers but is impaired. SYMPHONY records it with a 25% error rate.

## `GET /logs`

```json
{ "entries": [ { "level": "INFO | WARN | ERROR", "message": "text" } ] }
```

Return recent entries, oldest first. Extra fields such as `time` are kept. If `/logs` fails, SYMPHONY records a single `ERROR` entry describing the failure rather than returning nothing.

## `GET /traces`

```json
{ "requests": [ { "target_id": "payment", "status_code": 200 } ] }
```

Each item is one outgoing request this service made. `target_id` is the **SYMPHONY service ID** of the callee, not a hostname. SYMPHONY turns each item into a span:

| `status_code` | Outcome |
| --- | --- |
| below 400 | `ok` |
| 504 | `timeout` |
| other, 400 or above | `error_503` |

These spans are the only way SYMPHONY learns about undocumented dependencies. A dependency is accepted only when the trace evidence names the exact caller and callee.

## Run and evidence behavior

SYMPHONY keeps its own run ID in real mode.

- The run ID is `real-<n>`. It changes only when the set of service states changes, for example when a service goes from `healthy` to `down`, and not on every poll.
- Evidence collected in one run cannot support a conclusion in a later run. Agent results, scans and assessments from an earlier run are discarded.
- Evidence is kept in memory for the current run only. At most `SYMPHONY_EVIDENCE_LIMIT` records are kept (default 500, minimum 10) and the oldest are dropped first. Health polling does not create evidence.
- Everything is lost on restart. Persistence is a later step.

## Known gaps in real mode

- Accepted dependency discoveries are stored in the simulator's graph state. They survive run changes but not a restart.
- The Recovery agent's repair preview still runs on the simulator, which has no incident in real mode, so it cannot verify a repair against real services. Treat its output there as a recommendation only.
- Impact analysis uses the known dependency graph combined with observed health. It does not read live traffic.

## Reference implementation

`reference_stack/` contains a standard-library Python service and a Docker Compose file that implement this contract.

```sh
docker compose -f reference_stack/docker-compose.yml up --build -d
SYMPHONY_SERVICE_MODE=real jac start --dev main.jac
docker compose -f reference_stack/docker-compose.yml stop auth     # real incident
docker compose -f reference_stack/docker-compose.yml start auth    # recover
```

Payment calls Auth although the documented graph does not list that link, so the Investigator can discover it from traces. A service reports itself `down` when a dependency it calls is failing, so stopping `auth` also takes down `payment`, `api_gateway` and `frontend`, like the simulated Auth outage.

For demos, each service also accepts `POST /admin/state` with `{"state": "healthy | degraded | down"}`. It is not part of the contract and SYMPHONY never calls it. Turn it off with `ADMIN_ENABLED=false`.
