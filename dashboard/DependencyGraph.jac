"""Fixed-position documented service topology."""

import from ..contracts { Service }

def service_state(services: list[Service], service_id: str) -> str {
    for service in services {
        if service.id == service_id {
            return service.state;
        }
    }
    return "healthy";
}

def ServiceNode(
    services: list[Service], service_id: str, name: str, class_name: str
) -> JsxElement {
    state = service_state(services, service_id);
    <div className={f"service-node {class_name} state-{state}"}>
        <span className="node-state"></span>
        <div>
            <strong>{name}</strong>
            <small>{state}</small>
        </div>
    </div>
}

def:pub DependencyGraph(services: list[Service]) -> JsxElement {
    <section className="panel graph-panel" aria-labelledby="graph-title">
        <div className="panel-heading">
            <div>
                <p className="section-kicker">Documented view</p>
                <h2 id="graph-title">Service dependency graph</h2>
            </div>
            <div className="legend"><span></span> Healthy</div>
        </div>
        <div className="graph-canvas">
            <svg
                className="graph-lines"
                viewBox="0 0 1000 440"
                preserveAspectRatio="none"
                aria-hidden="true"
            >
                <defs>
                    <marker
                        id="arrow"
                        markerWidth="8"
                        markerHeight="8"
                        refX="7"
                        refY="4"
                        orient="auto"
                    >
                        <path d="M0,0 L8,4 L0,8 Z"></path>
                    </marker>
                </defs>
                <path d="M190 220 L315 220" markerEnd="url(#arrow)"></path>
                <path d="M455 205 L575 115" markerEnd="url(#arrow)"></path>
                <path d="M455 235 L575 325" markerEnd="url(#arrow)"></path>
                <path
                    d="M715 115 C790 115 780 300 835 315"
                    markerEnd="url(#arrow)"
                ></path>
                <path d="M715 325 L835 325" markerEnd="url(#arrow)"></path>
            </svg>
            <div className="signal-rail" aria-hidden="true"></div>
            <ServiceNode
                services={services}
                service_id="frontend"
                name="Frontend"
                class_name="node-frontend"
            />
            <ServiceNode
                services={services}
                service_id="api_gateway"
                name="API Gateway"
                class_name="node-gateway"
            />
            <ServiceNode
                services={services}
                service_id="payment"
                name="Payment"
                class_name="node-payment"
            />
            <ServiceNode
                services={services}
                service_id="catalog"
                name="Catalog"
                class_name="node-catalog"
            />
            <ServiceNode
                services={services}
                service_id="auth"
                name="Auth"
                class_name="node-auth"
            />
            <ServiceNode
                services={services}
                service_id="database"
                name="Database"
                class_name="node-database"
            />
        </div>
        <p className="panel-footnote">
            Only documented relationships are visible. Runtime discoveries require diagnostic evidence.
        </p>
    </section>
}
