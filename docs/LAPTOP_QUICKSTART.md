# Laptop Quickstart — Run Bluespeed on Your Machine

You don't need a homelab. Bluespeed runs on your laptop with the same
stack and tooling as the ghost cluster.

## Minimum Hardware

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM      | 8 GB    | 16 GB       |
| CPU      | 4 cores | 8 cores     |
| Disk     | 40 GB   | 80 GB+ SSD  |
| OS       | Linux (Fedora, Bluefin, Ubuntu, Debian) |

If you're below these specs, k3s + OTel + Loki + Prometheus together can
still run but you'll feel it under load. Close browser tabs and heavy apps
before starting.

## Quickstart

```bash
# 1. Clone the repo
git clone https://github.com/projectbluefin/bluespeed
cd bluespeed

# 2. Run the local setup recipe (no SSH, no remote nodes)
just setup-local
```

`just setup-local` installs k3s in single-node mode, deploys the Ghost
dashboard, and wires up the observability stack — all on localhost.

## What Gets Installed

- **k3s** — single-node Kubernetes (no worker nodes, no Helm controller)
- **Ghost: Bluespeed dashboard** — KubeStellar WebUI
- **OTel Collector** — receives metrics, traces, and logs on standard ports
- **Loki** (3100) — log aggregation
- **Prometheus** (9090) — metrics store
- **Perses** (8082) — dashboards

All services bind to `localhost` by default. Open `http://localhost:8082`
in a browser to see the dashboard.

## Immutable OS (Bluefin / Fedora Silverblue)

k3s's install script writes to `/usr/local/bin`, which does not survive
an ostree transaction on immutable systems. Two options:

### Option A: Install in your home directory (recommended)

k3s supports `INSTALL_K3S_BIN_DIR`:

```bash
export INSTALL_K3S_BIN_DIR="$HOME/.local/bin"
just setup-local
```

Ensure `$HOME/.local/bin` is in your `PATH` (it usually is on Bluefin).

### Option B: Layer k3s via rpm-ostree

```bash
rpm-ostree install k3s k3s-selinux
# reboot, then:
just setup-local SKIP_K3S_INSTALL=1
```

The `SKIP_K3S_INSTALL=1` flag tells the Justfile to use the layered
binary instead of running the install script.

## Verifying the Stack

```bash
just cluster-status          # check cluster health
just otel-status HOST=localhost  # check observability stack
```

## After You're Done

```bash
just teardown-local          # stop k3s and clean up
```

## Troubleshooting

### Port conflicts

Bluespeed uses ports 3100, 4317, 4318, 9090, and 8082. If any of these
are in use, stop the conflicting service first:

```bash
ss -tlnp | grep -E '3100|4317|4318|9090|8082'
```

### SELinux (Bluefin / Fedora)

If k3s fails with SELinux denials, install the policy:

```bash
sudo dnf install k3s-selinux   # mutable Fedora
# or
rpm-ostree install k3s-selinux # immutable/Bluefin (requires reboot)
```

### k3s won't start after reboot

On single-node setups, k3s expects to find its data directory. If you
moved or deleted `/var/lib/rancher/k3s`, re-run `just setup-local`.

## Next Steps

Once the local stack is running, send your laptop's telemetry to the
fleet dashboard:

```bash
just setup-otel-agent HOST=localhost
```

Your laptop will appear as a fleet member in the Ghost dashboard. From
there you can manage workloads, check logs, and contribute to Bluefin
development — all from your own machine.
