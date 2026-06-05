# Actionable Tasks: Implementation Notes

## TLS for homelab services (#36)
Deploy cert-manager + Let's Encrypt for KubeStellar console and KubeVirt Manager.
See: https://cert-manager.io/docs/ for setup instructions.

## Decommission Podman Quadlets (#24)
After k3s migration validated, remove remaining podman quadlet configs:
```
systemctl disable podman-quadlet@*.service
rm -rf /etc/containers/systemd/*.quadlet
```

## Deploy OTel Collector (#22)
Deploy OTel collector aggregator via Helm chart:
```
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install otel-collector open-telemetry/opentelemetry-collector -f otel-values.yaml
```

## Deploy Loki and Prometheus (#21)
Deploy Loki for logs and Prometheus for metrics via k3s:
```
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack
```

## Cluster-status health check recipe (#19)
Add `just cluster-status` recipe to Justfile that runs:
- `kubectl get nodes`
- `kubectl get pods -A | grep -v Running`
- `kubectl top nodes`

## Codify Flatcar VM creation (#26)
Create `just create-vm` recipe that wraps `bvck ephemeral create`.
