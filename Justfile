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

# ── KubeStellar Console ─────────────────────────────────────────────────────

# Install KubeStellar Console binaries on ghost and create systemd user services
# Prereq: kubeconfig at /tmp/exo-knuckle-kubeconfig.yaml on ghost
# Usage: just install-kubestellar-console
install-kubestellar-console:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST=jorge@192.168.1.102
    echo "→ Copying install script to ghost..."
    scp kubestellar/install.sh ${GHOST}:/tmp/ks-install.sh
    echo "→ Running install on ghost..."
    ssh ${GHOST} "bash /tmp/ks-install.sh"

# Check KubeStellar Console health on ghost
kubestellar-status:
    #!/usr/bin/env bash
    GHOST=jorge@192.168.1.102
    GHOST_IP=192.168.1.102
    echo "=== KubeStellar Console ==="
    curl -sf "http://${GHOST_IP}:8090/" > /dev/null && echo " ✅ http://${GHOST_IP}:8090" || echo " ❌ not reachable"
    echo "=== Service status ==="
    ssh ${GHOST} "systemctl --user is-active kubestellar-agent.service kubestellar-console.service"
    echo "=== Cluster count ==="
    ssh ${GHOST} "tail -3 ~/kubestellar-console/kc-agent.log | grep -o 'clusters:[0-9]*' || echo 'check log manually'"

# Restart KubeStellar Console services on ghost
kubestellar-restart:
    ssh jorge@192.168.1.102 "systemctl --user restart kubestellar-agent.service kubestellar-console.service"
    @echo "✓ KubeStellar Console restarted"

# Tail KubeStellar Console logs on ghost
kubestellar-logs:
    ssh jorge@192.168.1.102 "journalctl --user -f -u kubestellar-agent -u kubestellar-console"

# Rename knuckle-1 VM (requires shutdown — will disrupt k3s briefly)
# Usage: just rename-vm OLD=exo-knuckle NEW=knuckle-1
rename-vm OLD NEW:
    #!/usr/bin/env bash
    GHOST=jorge@192.168.1.102
    echo "→ Shutting down {{OLD}}..."
    ssh ${GHOST} "sudo virsh shutdown {{OLD}}"
    sleep 15
    ssh ${GHOST} "sudo virsh domrename {{OLD}} {{NEW}} && sudo virsh start {{NEW}}"
    echo "→ Waiting for k3s to come back up..."
    sleep 30
    ssh ${GHOST} "ssh -o StrictHostKeyChecking=no core@192.168.122.227 '/opt/bin/k3s kubectl get nodes'"
    @echo "✓ VM renamed {{OLD}} → {{NEW}}"

# ── Exo Fleet Registry ──────────────────────────────────────────────────────

# Register a new Exo node in the fleet
# Usage: just exo-register CALLSIGN=yourname
exo-register CALLSIGN:
    @echo "→ Registering {{CALLSIGN}}-1 in exos/registry.yaml"
    @echo "TODO: implement exo-register"

# Increment your Exo's reset number after a merged fix
# Usage: just exo-reset CALLSIGN=yourname
exo-reset CALLSIGN:
    @echo "→ Resetting {{CALLSIGN}} — opening PR to increment number"
    @echo "TODO: implement exo-reset"

# ── Raptor Control Center Dashboard ─────────────────────────────────────────

# Deploy Raptor Control Center dashboard to ghost (serves on :8091)
# Usage: just serve-dashboard HOST=jorge@192.168.1.102
serve-dashboard HOST="jorge@192.168.1.102":
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST={{HOST}}
    GHOST_IP=$(echo "{{HOST}}" | cut -d@ -f2)
    echo "→ Syncing dashboard files to ${GHOST}..."	
    rsync -av --delete dashboard/ ${GHOST}:~/bluespeed-dashboard/
    rsync -av exos/registry.yaml ${GHOST}:~/bluespeed-dashboard/../exos/ 2>/dev/null || true
    echo "→ Running serve.sh on ghost..."
    ssh ${GHOST} "cd ~/bluespeed-dashboard && bash serve.sh"
    echo ""
    echo "🦖 Dashboard URL: http://${GHOST_IP}:8091"

# Check dashboard status on ghost
dashboard-status HOST="jorge@192.168.1.102":
    #!/usr/bin/env bash
    GHOST_IP=$(echo "{{HOST}}" | cut -d@ -f2)
    echo "=== Dashboard ==="
    curl -sf "http://${GHOST_IP}:8091/" > /dev/null && echo " ✅ http://${GHOST_IP}:8091" || echo " ❌ not reachable"
    echo "=== Container ==="
    ssh {{HOST}} "podman ps --filter name=bluespeed-dashboard --format 'Status: {{.Status}} | Image: {{.Image}}'" 2>/dev/null || echo " (ssh failed)"

# Restart the dashboard container on ghost
dashboard-restart HOST="jorge@192.168.1.102":
    ssh {{HOST}} "podman restart bluespeed-dashboard"
    @echo "✓ Dashboard restarted"

# View dashboard container logs on ghost
dashboard-logs HOST="jorge@192.168.1.102":
    ssh {{HOST}} "podman logs -f bluespeed-dashboard"

# ── Argo Workflows ───────────────────────────────────────────────────────────

# Install Argo Workflows + Argo Events on knuckle-1 via k3s auto-deploy
# Usage: just setup-argo HOST=core@192.168.122.227
setup-argo HOST="core@192.168.122.227":
    @echo "→ Installing Argo Workflows on {{HOST}}..."
    bash argo/install.sh {{HOST}}

# Check Argo Workflows + Events pod status
argo-status HOST="core@192.168.122.227":
    ssh jorge@192.168.1.102 "ssh {{HOST}} '/opt/bin/k3s kubectl get pods -n argo; echo; /opt/bin/k3s kubectl get pods -n argo-events'"

# Open Argo Workflows UI (socat proxy on ghost → knuckle-1:32746)
argo-ui:
    @echo "Argo Workflows UI: https://192.168.1.102:2746"

# Start/restart the socat proxy that forwards ghost:2746 → knuckle-1:32746
argo-proxy-start:
    ssh jorge@192.168.1.102 "systemctl --user enable --now argo-ui-proxy.service && systemctl --user is-active argo-ui-proxy.service"
    @echo "✓ Argo UI proxy running: https://192.168.1.102:2746"

# Stop the socat proxy
argo-proxy-stop:
    ssh jorge@192.168.1.102 "systemctl --user stop argo-ui-proxy.service"
    @echo "✓ Argo UI proxy stopped"

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
