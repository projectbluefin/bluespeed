#!/usr/bin/env bash
# Deploy OTel observability stack to the central (ghost) node.
# Usage: ./deploy.sh jorge@192.168.1.102
set -euo pipefail

HOST=${1:?usage: deploy.sh user@host}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="/var/home/jorge/bluespeed/otel"
IP=$(echo "$HOST" | cut -d@ -f2)

echo "→ Creating remote directories..."
ssh "$HOST" "mkdir -p ${REMOTE_DIR}/config/perses ${REMOTE_DIR}/{loki-data,prometheus-data,perses-data} && chmod 777 ${REMOTE_DIR}/{loki-data,prometheus-data,perses-data}"

echo "→ Copying configs..."
scp "${SCRIPT_DIR}/ghost/config/otelcol-config.yaml" "${HOST}:${REMOTE_DIR}/config/"
scp "${SCRIPT_DIR}/ghost/config/loki-config.yaml"    "${HOST}:${REMOTE_DIR}/config/"
scp "${SCRIPT_DIR}/ghost/config/prometheus.yml"       "${HOST}:${REMOTE_DIR}/config/"
scp "${SCRIPT_DIR}/ghost/config/perses-config.yaml"   "${HOST}:${REMOTE_DIR}/config/"

echo "→ Installing Quadlets..."
ssh "$HOST" "mkdir -p ~/.config/containers/systemd"
scp "${SCRIPT_DIR}/ghost/quadlets/observability.network" "${HOST}:~/.config/containers/systemd/"
scp "${SCRIPT_DIR}/ghost/quadlets/loki.container"        "${HOST}:~/.config/containers/systemd/"
scp "${SCRIPT_DIR}/ghost/quadlets/prometheus.container"  "${HOST}:~/.config/containers/systemd/"
scp "${SCRIPT_DIR}/ghost/quadlets/otelcol.container"     "${HOST}:~/.config/containers/systemd/"
scp "${SCRIPT_DIR}/ghost/quadlets/perses.container"      "${HOST}:~/.config/containers/systemd/"

echo "→ Reloading systemd..."
ssh "$HOST" "systemctl --user daemon-reload"

echo "→ Starting services (in order)..."
ssh "$HOST" "
  systemctl --user start loki.service && sleep 5
  systemctl --user start prometheus.service && sleep 5
  systemctl --user start otelcol.service && sleep 8
  systemctl --user start perses.service
"

echo "→ Waiting for services to be ready (30s)..."
sleep 30

echo "→ Verifying health..."
curl -sf "http://${IP}:3100/ready"  > /dev/null && echo "  ✅ Loki ready"       || echo "  ⚠️  Loki not yet ready — check: ssh ${HOST} journalctl --user -u loki -n 20"
curl -sf "http://${IP}:9090/-/ready" > /dev/null && echo "  ✅ Prometheus ready" || echo "  ⚠️  Prometheus not yet ready"
curl -sf "http://${IP}:8888/metrics" > /dev/null && echo "  ✅ OTel Collector ready" || echo "  ⚠️  OTel Collector not yet ready"
curl -sf "http://${IP}:8082/api/v1/health" > /dev/null && echo "  ✅ Perses ready" || echo "  ⚠️  Perses not yet ready"

echo ""
echo "→ Provisioning Perses datasources..."

curl -sf -X POST "http://${IP}:8082/api/v1/globaldatasources" \
  -H 'Content-Type: application/json' \
  -d "{\"kind\":\"GlobalDatasource\",\"metadata\":{\"name\":\"Prometheus\"},\"spec\":{\"default\":true,\"plugin\":{\"kind\":\"PrometheusDatasource\",\"spec\":{\"directUrl\":\"http://${IP}:9090\"}}}}" \
  > /dev/null 2>&1 && echo "  ✅ Prometheus datasource" || echo "  ⚠️  Prometheus datasource (may already exist)"

curl -sf -X POST "http://${IP}:8082/api/v1/globaldatasources" \
  -H 'Content-Type: application/json' \
  -d "{\"kind\":\"GlobalDatasource\",\"metadata\":{\"name\":\"Loki\"},\"spec\":{\"default\":false,\"plugin\":{\"kind\":\"LokiDatasource\",\"spec\":{\"directUrl\":\"http://${IP}:3100\"}}}}" \
  > /dev/null 2>&1 && echo "  ✅ Loki datasource" || echo "  ⚠️  Loki datasource (may already exist)"

echo ""
echo "✅ Observability stack deployed to ${IP}"
echo ""
echo "   Perses (dashboards): http://${IP}:8082"
echo "   Prometheus (metrics): http://${IP}:9090"
echo "   Loki (logs):         http://${IP}:3100"
