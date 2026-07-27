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

# Configure nginx proxy for KubeStellar: serves HTTPS:8090, injects live-mode defaults into every page
# Run after install-kubestellar-console. Sets demo mode OFF and user identity for all browsers.
# USERNAME: linux username to show in the console top-right (default: jorge)
configure-kubestellar-proxy USERNAME="jorge":
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST=jorge@192.168.1.102
    GHOST_IP=192.168.1.102
    LINUX_USER={{USERNAME}}
    INIT_SCRIPT="localStorage.setItem(\\\"kc-demo-mode\\\",\\\"false\\\");if(!localStorage.getItem(\\\"kc-user-cache\\\"))localStorage.setItem(\\\"kc-user-cache\\\",JSON.stringify({id:\\\"local-${LINUX_USER}\\\",github_id:\\\"local-${LINUX_USER}\\\",github_login:\\\"${LINUX_USER}\\\",role:\\\"admin\\\",onboarded:true}));"
    ssh ${GHOST} "mkdir -p ~/certs/nginx && cat > ~/certs/nginx/nginx.conf << NGINXEOF
events {}
http {
    server {
        listen 8090 ssl;
        ssl_certificate     /certs/192.168.1.102+3.pem;
        ssl_certificate_key /certs/192.168.1.102+3-key.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;
        location / {
            proxy_pass http://127.0.0.1:9191;
            proxy_set_header Host \\\$host;
            sub_filter '</head>' '<script>${INIT_SCRIPT}</script></head>';
            sub_filter_once  on;
            sub_filter_types text/html;
        }
    }
}
NGINXEOF
systemctl --user enable --now kubestellar-proxy.service"
    @echo "✓ KubeStellar proxy → https://${GHOST_IP}:8090 (live mode, user: {{USERNAME}})"

# Check KubeStellar Console health on ghost
kubestellar-status:
    #!/usr/bin/env bash
    GHOST=jorge@192.168.1.102
    GHOST_IP=192.168.1.102
    echo "=== KubeStellar Console ==="
    curl -sfk "https://${GHOST_IP}:8090/" > /dev/null && echo " ✅ https://${GHOST_IP}:8090 (TLS, live mode)" || echo " ❌ not reachable"
    echo "=== Service status ==="
    ssh ${GHOST} "systemctl --user is-active kubestellar-agent.service kubestellar-agent-proxy.service kubestellar-console.service kubestellar-proxy.service"
    echo "=== Cluster count ==="
    ssh ${GHOST} "tail -3 ~/kubestellar-console/kc-agent.log | grep -o 'clusters:[0-9]*' || echo 'check log manually'"

# Restart KubeStellar Console services on ghost
kubestellar-restart:
    ssh jorge@192.168.1.102 "systemctl --user restart kubestellar-agent.service kubestellar-agent-proxy.service kubestellar-console.service kubestellar-proxy.service"
    @echo "✓ KubeStellar Console restarted — https://ghost.tail2a28a.ts.net:8090"

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

# ── TLS / Tailscale cert ──────────────────────────────────────────────────────

# Renew the Tailscale Let's Encrypt cert for ghost (valid 90 days, run ~every 60d)
# No browser import needed — trusted everywhere by default
tls-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST=jorge@192.168.1.102
    ssh ${GHOST} "tailscale cert ghost.tail2a28a.ts.net && cp ghost.tail2a28a.ts.net.crt ~/certs/ && cp ghost.tail2a28a.ts.net.key ~/certs/"
    ssh ${GHOST} "systemctl --user restart kubestellar-proxy"
    echo "✓ Tailscale cert renewed. KubeStellar: https://ghost.tail2a28a.ts.net:8090"

# ── KubeVirt ──────────────────────────────────────────────────────────────────

# Install KubeVirt operator + CR into k3s on knuckle-1
install-kubevirt:
    #!/usr/bin/env bash
    set -euo pipefail
    KNUCKLE=core@192.168.122.227
    VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
    echo "→ Installing KubeVirt ${VERSION}..."
    ssh jorge@192.168.1.102 "ssh ${KNUCKLE} 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; sudo -E kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml; sudo -E kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml; sudo -E kubectl -n kubevirt wait kv kubevirt --for condition=Available --timeout=300s'"
    echo "✓ KubeVirt ${VERSION} ready"

# Install CDI (disk image import/clone) into k3s on knuckle-1
install-cdi:
    #!/usr/bin/env bash
    set -euo pipefail
    KNUCKLE=core@192.168.122.227
    VERSION=$(curl -sL https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | head -1)
    echo "→ Installing CDI ${VERSION}..."
    ssh jorge@192.168.1.102 "ssh ${KNUCKLE} 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; sudo -E kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/${VERSION}/cdi-operator.yaml; sudo -E kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/${VERSION}/cdi-cr.yaml; sudo -E kubectl -n cdi wait cdi cdi --for condition=Available --timeout=300s'"
    echo "✓ CDI ${VERSION} ready"

# Install KubeVirt Manager web UI — noVNC console at http://192.168.1.102:30180
install-kubevirt-manager:
    #!/usr/bin/env bash
    set -euo pipefail
    KNUCKLE=core@192.168.122.227
    ssh jorge@192.168.1.102 "ssh ${KNUCKLE} 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; sudo -E kubectl apply -f https://raw.githubusercontent.com/kubevirt-manager/kubevirt-manager/main/kubernetes/bundled.yaml; sudo -E kubectl -n kubevirt-manager patch svc kubevirt-manager --type=merge --patch '"'"'{"spec":{"type":"NodePort","ports":[{"port":8080,"nodePort":30180}]}}'"'"''"
    ssh jorge@192.168.1.102 "systemctl --user enable --now kubevirt-manager-proxy.service"
    @echo "✓ KubeVirt Manager → http://192.168.1.102:30180"

# Start KubeVirt Manager socat proxy (ghost:30180 → knuckle-1:30180)
kubevirt-manager-proxy-start:
    ssh jorge@192.168.1.102 "systemctl --user enable --now kubevirt-manager-proxy.service && systemctl --user is-active kubevirt-manager-proxy.service"
    @echo "✓ KubeVirt Manager: http://192.168.1.102:30180"

# Apply all Titan VM manifests (titan-dakota, titan-stable, titan-lts)
install-titans:
    #!/usr/bin/env bash
    set -euo pipefail
    KNUCKLE=core@192.168.122.227
    ssh jorge@192.168.1.102 "ssh ${KNUCKLE} 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; sudo -E kubectl apply -f /tmp/titan-dakota.yaml; sudo -E kubectl apply -f /tmp/titan-stable.yaml; sudo -E kubectl apply -f /tmp/titan-lts.yaml'"
    @echo "✓ Titan manifests applied — DataVolume import will begin"

# Start a Titan VM
# Usage: just titan-start dakota
titan-start VARIANT:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    ssh ${GHOST} "ssh ${KNUCKLE1} 'sudo virtctl start titan-{{VARIANT}} -n default'"
    echo "→ titan-{{VARIANT}} starting — watching VMI..."
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} wait --for=condition=ready vmi/titan-{{VARIANT}} --timeout=120s'" || true
    echo "✓ Open http://192.168.1.102:30190/guacamole/ → titan-{{VARIANT}}"

# Stop a Titan VM
# Usage: just titan-stop dakota
titan-stop VARIANT:
    #!/usr/bin/env bash
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    ssh ${GHOST} "ssh ${KNUCKLE1} 'sudo virtctl stop titan-{{VARIANT}} -n default'"
    echo "✓ titan-{{VARIANT}} stopped"

# Status of all Titans
# Usage: just titan-status
titan-status:
    #!/usr/bin/env bash
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    echo "=== Titan VMs ==="
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} get vm -l titan=true'"
    echo "=== DataVolumes ==="
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} get dv 2>/dev/null | grep titan || echo none'"
    echo "=== kvnc-proxy pods ==="
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} get pods -l titan=true'"
    echo "Console: http://192.168.1.102:30190/guacamole/"

# Open Titan console via Guacamole
titan-console VARIANT:
    @echo "Open http://192.168.1.102:30190/guacamole/ → titan-{{VARIANT}}"

# KubeVirt full health check
kubevirt-status:
    #!/usr/bin/env bash
    KNUCKLE=core@192.168.122.227
    ssh jorge@192.168.1.102 "ssh ${KNUCKLE} 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; sudo -E kubectl -n kubevirt get pods; echo; sudo -E kubectl -n cdi get pods; echo; sudo -E kubectl get vms -A 2>/dev/null || echo \"(no VMs yet)\"'"
    echo "KubeVirt Manager: http://192.168.1.102:30180"

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

# ── Guacamole Console ─────────────────────────────────────────────────────────

# One-time: create the guacamole-db-secret in knuckle-1 (generates random password)
# Usage: just create-guac-secret
create-guac-secret:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    PASS=$(openssl rand -base64 20 | tr -dc 'a-zA-Z0-9' | head -c 24)
    ssh ${GHOST} "ssh ${KNUCKLE1} \
      '${KBC} create secret generic guacamole-db-secret \
        -n guacamole \
        --from-literal=password=${PASS} \
        --dry-run=client -o yaml | ${KBC} apply -f -'"
    echo "✓ guacamole-db-secret created (password stored in k8s secret only)"

# Deploy full Guacamole stack: namespace → secret check → postgres → guacd → webapp → initdb
# Usage: just install-guacamole
install-guacamole:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    MANIFESTS=(
      guacamole/namespace.yaml
      guacamole/postgres.yaml
      guacamole/guacd.yaml
      guacamole/guacamole.yaml
    )
    echo "→ Uploading and applying Guacamole manifests..."
    for f in "${MANIFESTS[@]}"; do
      scp "$f" ${GHOST}:/tmp/$(basename $f)
      ssh ${GHOST} "scp /tmp/$(basename $f) ${KNUCKLE1}:/tmp/ && \
        ssh ${KNUCKLE1} '${KBC} apply -f /tmp/$(basename $f)'"
    done
    echo "→ Waiting for postgres to be ready..."
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} wait --for=condition=available deployment/postgres -n guacamole --timeout=120s'"
    echo "→ Running initdb job..."
    scp guacamole/initdb-job.yaml ${GHOST}:/tmp/initdb-job.yaml
    ssh ${GHOST} "scp /tmp/initdb-job.yaml ${KNUCKLE1}:/tmp/ && \
      ssh ${KNUCKLE1} '${KBC} apply -f /tmp/initdb-job.yaml'"
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} wait --for=condition=complete job/guacamole-initdb -n guacamole --timeout=120s'"
    echo "→ Waiting for guacamole webapp..."
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} wait --for=condition=available deployment/guacamole -n guacamole --timeout=120s'"
    echo "✓ Guacamole ready → http://192.168.1.102:30190/guacamole/"
    echo "  Default login: guacadmin / guacadmin (change immediately)"

# Check Guacamole stack status
# Usage: just guacamole-status
guacamole-status:
    #!/usr/bin/env bash
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    GHOST_IP="192.168.1.102"
    echo "=== Guacamole pods ==="
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} get pods -n guacamole'"
    echo "=== Web UI ==="
    curl -sf --max-time 5 "http://${GHOST_IP}:30190/guacamole/" > /dev/null && \
      echo " ✅ http://${GHOST_IP}:30190/guacamole/" || echo " ❌ not reachable"

# ── Titan VM Fleet ─────────────────────────────────────────────────────────────

# One-time: configure CDI to allow insecure pulls from ghost zot (192.168.1.102:5000)
# Usage: just titan-cdi-patch
titan-cdi-patch:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    scp kubevirt/cdi-insecure-registry.yaml ${GHOST}:/tmp/cdi-insecure-registry.yaml
    ssh ${GHOST} "scp /tmp/cdi-insecure-registry.yaml ${KNUCKLE1}:/tmp/ && \
      ssh ${KNUCKLE1} '${KBC} apply -f /tmp/cdi-insecure-registry.yaml'"
    echo "✓ CDI insecure registry configured for 192.168.1.102:5000"

# One-time: deploy kvnc-proxy RBAC + titan-dakota VNC proxy
# Usage: just titan-deploy-proxy
titan-deploy-proxy:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    for f in kvnc-proxy/rbac.yaml kvnc-proxy/titan-dakota-proxy.yaml; do
      scp "$f" ${GHOST}:/tmp/$(basename $f)
      ssh ${GHOST} "scp /tmp/$(basename $f) ${KNUCKLE1}:/tmp/ && \
        ssh ${KNUCKLE1} '${KBC} apply -f /tmp/$(basename $f)'"
    done
    echo "✓ kvnc-proxy deployed — waiting for proxy pod..."
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} wait --for=condition=available deployment/titan-dakota-vnc-proxy --timeout=120s'"
    echo "✓ titan-dakota-vnc.default.svc.cluster.local:5900 ready"

# Import titan-dakota disk from ghost zot (takes ~5-10 min)
# Usage: just titan-create-dakota
titan-create-dakota:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    scp kubevirt/titan-dakota.yaml ${GHOST}:/tmp/titan-dakota.yaml
    ssh ${GHOST} "scp /tmp/titan-dakota.yaml ${KNUCKLE1}:/tmp/ && \
      ssh ${KNUCKLE1} '${KBC} apply -f /tmp/titan-dakota.yaml'"
    echo "→ DataVolume import started — polling status (may take 5-10 min)..."
    while true; do
      STATUS=$(ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} get dv titan-dakota-disk -o jsonpath={.status.phase} 2>/dev/null || echo Unknown'")
      echo "  DataVolume: ${STATUS}"
      [ "${STATUS}" = "Succeeded" ] && break
      [ "${STATUS}" = "Failed" ] && echo "❌ Import failed" && exit 1
      sleep 15
    done
    echo "✓ titan-dakota-disk imported"

# Re-provision titan-dakota from latest zot image
# Usage: just titan-reprovision-dakota
titan-reprovision-dakota:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    KNUCKLE1="core@192.168.122.227"
    KBC="sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml"
    echo "→ Stopping titan-dakota..."
    ssh ${GHOST} "ssh ${KNUCKLE1} 'sudo virtctl stop titan-dakota -n default 2>/dev/null || true'"
    sleep 5
    echo "→ Deleting old DataVolume..."
    ssh ${GHOST} "ssh ${KNUCKLE1} '${KBC} delete dv titan-dakota-disk --ignore-not-found'"
    echo "→ Re-importing from 192.168.1.102:5000/dakota:latest..."
    just titan-create-dakota

# Add persistent socat forward on ghost for Guacamole (port 30190 → knuckle-1:30190)
# Usage: just ghost-add-guac-forward
ghost-add-guac-forward:
    #!/usr/bin/env bash
    set -euo pipefail
    GHOST="jorge@192.168.1.102"
    ssh ${GHOST} 'cat > /tmp/socat-guacamole.service << '"'"'SVCEOF'"'"'
[Unit]
Description=socat forward: ghost:30190 -> knuckle-1:30190 (Guacamole)
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:30190,fork,reuseaddr TCP:192.168.122.227:30190
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF
mkdir -p ~/.config/systemd/user
mv /tmp/socat-guacamole.service ~/.config/systemd/user/socat-guacamole.service
systemctl --user daemon-reload
systemctl --user enable --now socat-guacamole.service
systemctl --user is-active socat-guacamole.service'
    echo "✓ ghost:30190 → 192.168.122.227:30190 forwarding active"

# ── Fleet Node Management ────────────────────────────────────────────────────

# Create a Flatcar VM for the bluespeed fleet
# Usage: just create-vm exo2 HOST=jorge@192.168.1.100 RAM=16384 VCPUS=8 DISK=60G
create-vm NAME HOST RAM="16384" VCPUS="8" DISK="60G":
    @echo "→ Creating fleet node: {{NAME}}..."
    bash vms/create-vm.sh "{{NAME}}" "{{HOST}}" "{{RAM}}" "{{VCPUS}}" "{{DISK}}"

# Generate an ignition template for a new fleet node
# Usage: just ignition-template exo2
ignition-template NAME:
    @mkdir -p vms/ignition
    @echo "# Butane config for {{NAME}}" > vms/ignition/{{NAME}}.bu
    @echo "variant: flatcar" >> vms/ignition/{{NAME}}.bu
    @echo "version: 1.0.0" >> vms/ignition/{{NAME}}.bu
    @echo "passwd:" >> vms/ignition/{{NAME}}.bu
    @echo "  users:" >> vms/ignition/{{NAME}}.bu
    @echo "    - name: core" >> vms/ignition/{{NAME}}.bu
    @echo '      ssh_authorized_keys:' >> vms/ignition/{{NAME}}.bu
    @echo '        - "ssh-ed25519 YOUR_KEY_HERE"' >> vms/ignition/{{NAME}}.bu
    @echo "✓ Template created: vms/ignition/{{NAME}}.bu"
    @echo "  Edit it, then run: just create-vm {{NAME}} HOST=user@ip"
