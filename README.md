# Bluespeed

- We're going to use frontier models to build the best local-first homelab experience
- YOU DON'T NEED A HOMELAB, you can run this on your laptop or machine and have the same benefits. 
- By driving bluespeed with `just` we can make deterministic workflows - this means, the entire thing can be manually driven by just. So you never need AI. If you use AI you'll just go faster. And since everything will be as automated and declerative as we can make it means you can use your own local model to drive you automation.
- We basically want Star Trek + Jarvis. But local first. 

Bluespeed is a **homelab factory**. Clone this repo, run `just setup`, and get a fully reproducible homelab stack on your own bare-metal hardware — the same one the Project Bluefin team runs. Every tool in the stack is a CNCF project. No custom services where a CNCF tool exists. Everything is reproducible by any Bluefin contributor on their own hardware. 

### The first use case is Bluefin Development

- Fully automate Bluefin development.
  - Generalize Jorge's lab
- Build the MVP for Bluespeed which is knuckle + k3s + kubestellar
- Use hive and our agents to build and test everything.

### And then make justfiles so people without AI can help test Bluefin

- Users can opt in to ujust device 2.0 to send info back for us to fix!

---

## The Bundle

Bluespeed ships with **[knuckle](https://github.com/projectbluefin/knuckle)** as its installer.

**knuckle** is the standalone, upstream-track TUI installer for [Flatcar Container Linux](https://www.flatcar.org/) — neutral, minimal, and built to be what Flatcar's official installer could be. It lives in its own repo, has its own release cycle, and accepts no homelab opinions.

Bluespeed takes knuckle and adds the opinionated layer on top.

**knuckle:** installs Flatcar  
**Bluespeed:** configures everything you actually want on it

> The knuckle binary inside any Bluespeed release is always a tagged, unmodified knuckle release. Never forked. Never patched.

---

## The Stack

All CNCF projects. All reproducible. All deployed with `just`.

| Component | CNCF Status | Role |
|---|---|---|
| [knuckle](https://github.com/projectbluefin/knuckle) | — | Flatcar TUI installer |
| [OpenTelemetry Collector](https://opentelemetry.io/) | Incubating | Metrics + logs from every node |
| [Prometheus](https://prometheus.io/) | Graduated | Metrics storage |
| [Loki](https://grafana.com/oss/loki/) | Grafana Labs OSS | Log aggregation |
| [KubeStellar](https://kubestellar.io/) | Sandbox | Multi-cluster management — **Ghost: Bluespeed dashboard** |
| [KubeVirt](https://kubevirt.io/) | Incubating | VM management |

---

## Quick Start

**Laptop (single-node, no homelab):** see [Laptop Quickstart](docs/CONTRIBUTING.md#laptop-quickstart-single-node-no-homelab) in CONTRIBUTING.md.

**Homelab (multi-node, dedicated hardware):**

```bash
# 1. Install Flatcar on your hardware using knuckle
#    https://github.com/projectbluefin/knuckle/releases

# 2. Clone bluespeed
git clone https://github.com/projectbluefin/bluespeed
cd bluespeed

# 3. Deploy the observability stack to your central node
just setup-otel HOST=user@your-central-node

# 4. Deploy agents to your nodes
just setup-otel-agent HOST=user@node-1
just setup-otel-agent HOST=user@node-2

```

### Check cluster health

```bash
just cluster-status
```

---

## Observability Stack

The observability stack runs on your central node and collects metrics and logs from all nodes using OpenTelemetry.

### Architecture

```
node-1 ──► OTel Collector (agent)
node-2 ──► OTel Collector (agent) ──► OTel Collector (aggregator)
node-N ──►                                       │
                                     ┌───────────┼───────────┐
                                  (logs)     (metrics)  (dashboards)
```

### Ports

| Port | Service |
|---|---|
| 3100 | Loki |
| 4317 | OTel Collector gRPC (OTLP) |
| 4318 | OTel Collector HTTP (OTLP) |
| 9090 | Prometheus |

### Deploy

```bash
just setup-otel HOST=jorge@192.168.1.102
just setup-otel-agent HOST=jorge@192.168.1.247
just otel-status HOST=jorge@192.168.1.102
```

---

## Repository Layout

```
bluespeed/
├── Justfile                    # all operations live here
├── otel/                       # observability stack
│   ├── ghost/
│   │   ├── quadlets/           # Podman Quadlet definitions
│   ├── agent/                  # per-node OTel Collector agent
│   ├── deploy.sh               # deploys central-node stack
│   └── deploy-agent.sh         # deploys agent to a node
└── docs/
    └── CONTRIBUTING.md
```

---

## Design Principles

1. **CNCF first.** Every tool is a CNCF project. No custom services where a CNCF tool exists.
2. **Reproducible.** `just setup` on any compatible hardware produces the same result.
3. **Justfile-driven.** Every operation has a `just` recipe. No bespoke runbooks.
4. **Contributor-ready.** Any Bluefin contributor can deploy this on their own hardware.
5. **knuckle stays neutral.** Bluespeed bundles tagged knuckle releases as-is. Never patched.
6. **Clients consume images, they don't run cluster workloads.** Contributor laptops are managed via `bootc` image updates — not enrolled as k8s nodes. The cluster builds the images; the laptops boot them. This eliminates per-client agent overhead, enables atomic OS rollbacks, and keeps cluster complexity constant regardless of how many contributors join the fleet.

---

## Status

**Working today on ghost:**
- k3s single-node cluster on knuckle-1 (Flatcar VM via KVM)
- KubeStellar Console — Ghost: Bluespeed dashboard at `http://192.168.1.102:8090`
- Argo Workflows + Argo Events — build pipeline at `https://192.168.1.102:2746`
- Ghost: Bluespeed web panel at `http://192.168.1.102:8091`

**In progress:**
- OTel stack migration from Podman Quadlets → k3s
- `bluespeed.local` local DNS
- Custom Build dashboard (Argo Workflows + BlueBuild + Zot)

**Planned:**
- Exo fleet leaderboard panel
- KubeVirt VM management
- Node enrollment (`just setup-otel-agent HOST=...` already works)

---

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

---

## License

Apache-2.0 — see [LICENSE](LICENSE)
