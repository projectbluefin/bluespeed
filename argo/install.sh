#!/usr/bin/env bash
# Install Argo Workflows + Argo Events on a k3s node via auto-deploy dir
# Usage: bash argo/install.sh [core@host]
# Requires: curl, scp, ssh access to ghost (jorge@192.168.1.102)
# k3s auto-applies manifests from /var/lib/rancher/k3s/server/manifests/
set -euo pipefail

HOST=${1:-"core@192.168.122.227"}
GHOST="jorge@192.168.1.102"

# Pin to known-good versions (update here when bumping)
ARGO_VERSION="v4.0.5"
ARGO_EVENTS_VERSION="v1.9.10"

echo "→ Argo Workflows ${ARGO_VERSION}, Argo Events ${ARGO_EVENTS_VERSION}"

# Download manifests locally (GitHub API is rate-limited on ghost)
echo "→ Downloading manifests..."
curl -sfL "https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/install.yaml" \
  -o /tmp/argo-workflows.yaml
curl -sfL "https://raw.githubusercontent.com/argoproj/argo-events/${ARGO_EVENTS_VERSION}/manifests/install.yaml" \
  -o /tmp/argo-events.yaml

# Namespace manifest (install.yaml doesn't include Namespace — k3s needs it first)
cat > /tmp/00-namespaces.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: argo
---
apiVersion: v1
kind: Namespace
metadata:
  name: argo-events
EOF

# Upload to ghost, then to k3s node
echo "→ Uploading to ghost..."
scp /tmp/00-namespaces.yaml /tmp/argo-workflows.yaml /tmp/argo-events.yaml "${GHOST}":/tmp/

echo "→ Dropping into k3s auto-deploy dir on ${HOST}..."
ssh "${GHOST}" "
  ssh ${HOST} 'sudo mkdir -p /var/lib/rancher/k3s/server/manifests/argo'
  scp /tmp/00-namespaces.yaml /tmp/argo-workflows.yaml /tmp/argo-events.yaml ${HOST}:/tmp/
  ssh ${HOST} 'sudo mv /tmp/00-namespaces.yaml /tmp/argo-workflows.yaml /tmp/argo-events.yaml /var/lib/rancher/k3s/server/manifests/argo/'
"

echo "→ Waiting 30s for k3s to apply manifests..."
sleep 30

echo "→ Status:"
ssh "${GHOST}" "ssh ${HOST} '/opt/bin/k3s kubectl get pods -n argo -n argo-events 2>/dev/null'"

echo ""
echo "✅ Manifests dropped — k3s will apply within 30s"
echo "   Argo UI: https://192.168.1.102:2746 (via socat proxy on ghost)"
