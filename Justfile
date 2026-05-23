# bluespeed Justfile — CNCF homelab factory
# All operations live here. Run `just` to list recipes.

# Default: list all recipes
default:
    @just --list

# ── Observability Stack ───────────────────────────────────────────────────────

# Deploy full observability stack to a central node
# Usage: just setup-otel HOST=jorge@192.168.1.102
setup-otel HOST:
    @echo "→ Deploying OTel observability stack to {{HOST}}..."
    bash otel/deploy.sh {{HOST}}

# Deploy OTel Collector agent to a node
# Usage: just setup-otel-agent HOST=jorge@192.168.1.247
setup-otel-agent HOST:
    @echo "→ Deploying OTel agent to {{HOST}}..."
    bash otel/deploy-agent.sh {{HOST}}

# Check observability stack status on the central node
otel-status HOST:
    #!/usr/bin/env bash
    IP=$(echo "{{HOST}}" | cut -d@ -f2)
    echo "=== Loki ==="
    curl -sf "http://${IP}:3100/ready" && echo " ✅" || echo " ❌ not ready"
    echo "=== Prometheus ==="
    curl -sf "http://${IP}:9090/-/ready" && echo " ✅" || echo " ❌ not ready"
    echo "=== OTel Collector ==="
    curl -sf "http://${IP}:8888/metrics" | grep -c otelcol_process && echo " ✅" || echo " ❌ not ready"
    echo "=== Perses ==="
    curl -sf "http://${IP}:8082/api/v1/health" && echo " ✅" || echo " ❌ not ready"

# Tail logs from observability stack on central node
otel-logs HOST:
    ssh {{HOST}} "journalctl --user -f -u loki -u prometheus -u otelcol -u perses"

# Stop and remove observability stack
otel-teardown HOST:
    ssh {{HOST}} "systemctl --user stop loki prometheus otelcol perses 2>/dev/null || true && \
                  systemctl --user disable loki prometheus otelcol perses 2>/dev/null || true"
    @echo "✓ Observability stack stopped on {{HOST}}"

# ── Full Stack ────────────────────────────────────────────────────────────────

# Deploy everything: central node stack + agent on a second node
# Usage: just setup CENTRAL=user@your-central-node NODE=user@your-node
setup CENTRAL NODE:
    just setup-otel HOST={{CENTRAL}}
    just setup-otel-agent HOST={{NODE}}
    #!/usr/bin/env bash
    IP=$(echo "{{CENTRAL}}" | cut -d@ -f2)
    echo ""
    echo "✅ Bluespeed stack deployed"
    echo "   Perses (dashboards): http://${IP}:8082"
    echo "   Prometheus (metrics): http://${IP}:9090"
    echo "   Loki (logs):         http://${IP}:3100"
