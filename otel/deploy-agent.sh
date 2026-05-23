#!/usr/bin/env bash
# Deploy OTel Collector agent to a node as a systemd user service (binary install).
#
# Uses the statically-linked otelcol-contrib binary from the official OTel releases.
# Works on immutable OS (bootc/ostree) — no package manager required.
#
# Usage: ./deploy-agent.sh jorge@192.168.1.247
#
# Docs: https://opentelemetry.io/docs/collector/installation/
#       https://github.com/open-telemetry/opentelemetry-collector-releases
set -euo pipefail

HOST=${1:?usage: deploy-agent.sh user@host}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pin to a known-good version. Update both here and in agent config comments together.
OTELCOL_VERSION="0.152.1"
DOWNLOAD_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol-contrib_${OTELCOL_VERSION}_linux_amd64.tar.gz"

echo "→ Deploying OTel Collector agent v${OTELCOL_VERSION} to ${HOST}..."

echo "→ Creating directories..."
ssh "$HOST" "mkdir -p ~/.local/bin ~/.config/otelcol ~/.config/systemd/user"

echo "→ Downloading otelcol-contrib binary (${OTELCOL_VERSION})..."
ssh "$HOST" "
  set -e
  TMP=\$(mktemp -d)
  curl -fsSL '${DOWNLOAD_URL}' -o \"\${TMP}/otelcol-contrib.tar.gz\"
  tar -xzf \"\${TMP}/otelcol-contrib.tar.gz\" -C \"\${TMP}\"
  cp \"\${TMP}/otelcol-contrib\" ~/.local/bin/otelcol-contrib
  chmod +x ~/.local/bin/otelcol-contrib
  rm -rf \"\${TMP}\"
  echo '  ✅ binary installed at ~/.local/bin/otelcol-contrib'
  ~/.local/bin/otelcol-contrib --version
"

echo "→ Installing agent config..."
scp "${SCRIPT_DIR}/agent/otelcol-agent-config.yaml" "${HOST}:~/.config/otelcol/config.yaml"

echo "→ Installing systemd user service..."
scp "${SCRIPT_DIR}/agent/otelcol-agent.service" "${HOST}:~/.config/systemd/user/"

echo "→ Starting agent service..."
ssh "$HOST" "
  systemctl --user daemon-reload
  systemctl --user enable --now otelcol-agent.service
"

echo "→ Verifying (10s)..."
sleep 10
ssh "$HOST" "
  state=\$(systemctl --user is-active otelcol-agent.service 2>/dev/null)
  if [ \"\$state\" = 'active' ]; then
    echo '  ✅ otelcol-agent: active'
    journalctl --user -u otelcol-agent --no-pager -n 5 | grep -E 'Everything is ready|error|Error' || true
  else
    echo '  ❌ otelcol-agent: '\"\$state\"
    journalctl --user -u otelcol-agent --no-pager -n 20
    exit 1
  fi
"

echo ""
echo "✅ OTel agent v${OTELCOL_VERSION} deployed to ${HOST}"
echo "   Sending logs + metrics → ghost:4317 (OTLP gRPC)"
