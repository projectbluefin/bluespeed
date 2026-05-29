# Contributing to Bluespeed

## Philosophy

Bluespeed is a CNCF-native homelab factory. Before proposing any new tool or service, check whether a CNCF project covers the use case at [landscape.cncf.io](https://landscape.cncf.io/).

If a CNCF tool exists — use it. Don't build custom. This is non-negotiable.

## Hard Rules

These are non-negotiable. PRs that violate them will be closed.

### NO HELM

Helm is not used anywhere in this project. No Helm charts, no helmfile, no Helm operator, no Helm-based install scripts. All workloads are deployed as raw Kubernetes manifests (`Deployment`, `ConfigMap`, `Service`, `PVC`, etc.) through the Ghost: Bluespeed dashboard (KubeStellar WebUI). If an upstream project's official install method uses Helm, find the raw manifests or generate them once and commit them to the repo.

### NO kubectl apply

Contributors do not run `kubectl apply` directly. All workloads are deployed and managed through the **Ghost: Bluespeed dashboard** (KubeStellar WebUI). Justfile recipes handle any cluster interaction that requires direct API access.

### Deployment Surface

The **Ghost: Bluespeed dashboard** (KubeStellar WebUI) is the single deployment surface for all stack components. Install it immediately after k3s. Everything else goes through it.

### k3s is the Kubernetes distribution

k3s is the single source of truth. Do not reference k0s, k8s vanilla, or any other distribution. Install flags for a lean, CNCF-first setup:

```bash
--disable helm-controller
--disable traefik
--disable servicelb
--disable metrics-server
```

On Fedora/Bluefin (SELinux enabled): also add `--selinux` and install the `k3s-selinux` package first.

### HostPort, not NodePort

k3s default NodePort range is 30000–32767. All bluespeed service ports (3100, 4317, 4318, 9090, 8082) are below that floor. Use `hostPort` in pod specs with `hostNetwork: true` for all services that need to be reachable at their standard ports on the host network.

### Loki is not a CNCF project

Loki is a Grafana Labs OSS project, not a CNCF project. It is included in the stack because it is the best-in-class OTel log storage and there is no CNCF equivalent. Do not describe it as "CNCF Incubating" in documentation.

## Setting Up Your Own Lab

For a laptop-only setup (no remote nodes), see [docs/LAPTOP_QUICKSTART.md](docs/LAPTOP_QUICKSTART.md).

```bash
# Clone and deploy (multi-node lab)
git clone https://github.com/projectbluefin/bluespeed
cd bluespeed
just setup CENTRAL=user@your-central-node NODE=user@your-other-node
```

## Development Workflow

```bash
just                        # list all recipes
just setup-otel HOST=...    # deploy observability stack
just otel-status HOST=...   # check stack health
just otel-logs HOST=...     # tail service logs
```

## Adding a New Stack Component

1. Check [landscape.cncf.io](https://landscape.cncf.io/) — CNCF tool must exist
2. Add a `just` recipe in `Justfile`
3. Add deployment scripts under a new top-level directory (e.g. `kubevirt/`)
4. Document ports used — no conflicts with existing services:
   - 3100 Loki, 4317/4318 OTel, 9090 Prometheus, 8082 Perses
5. Update the stack table in `README.md`
6. Update `docs/CONTRIBUTING.md` with the new port

## Your laptop in the fleet

Your laptop is a **fleet member** — not a k8s node.

bluespeed deliberately does not run k8s agents on contributor laptops. Instead:

- Your laptop's OS is a **bootc image** built by the cluster (or built by the community and published to a registry)
- OS updates happen via `bootc upgrade` — atomic, with automatic rollback if the new image fails to boot
- You send observability data (metrics + logs) to ghost via a lightweight OTel Collector binary: `just setup-otel-agent HOST=localhost`
- Your laptop shows up in the Ghost: Bluespeed dashboard as a fleet member once the OTel agent is running

This design keeps cluster complexity constant regardless of how many contributors join — the cluster is always just ghost + knuckle-1. Your laptop never needs to know that k8s exists.

## Porting to New Hardware

The stack is designed to be hardware-agnostic. To deploy on different hardware:
- Update the `endpoint` in `otel/agent/otelcol-agent-config.yaml` to your central node IP
- Run `just setup CENTRAL=user@your-ip NODE=user@your-node-ip`

### Lore stays out of tech

The Destiny/Exo lore used in community documentation and issue descriptions is **never reflected in technical artifacts**. k8s node names, hostnames, DNS records, config files, systemd units, and Justfile recipes follow standard Linux/k8s naming conventions only. The `exos/registry.yaml` file contains lore metadata (descriptions, community names) but technical systems reference only hostnames. Do not put Destiny references in code.

## Issues

File issues at: https://github.com/projectbluefin/bluespeed/issues
