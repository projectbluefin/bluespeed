# AGENTS.md — Bluespeed Contributor Agent Instructions

For Hive and contributor AI agents working on this repo. Hard rules come first.

## Hard Rules

- **NO Helm.** Argo Workflows (CNCF) over Tekton (CDF).
- **k3s is the distribution.** Not kind, not minikube, not microk8s.
- **Loki is Grafana Labs OSS**, not a CNCF project — document accordingly.
- **Laptops are bootc clients, not k8s nodes.** They enroll via knuckle/fleet, not `kubectl join`.
- **Lore stays out of tech docs.** Keep README and AGENTS.md practical.
- **Bluespeed** (capital B) is the project name. "bluespeed" the CLI / directory name.

## Architecture

Three-tier model:

1. **Ghost hub** — single-node k3s controller plane (VM or bare metal). Runs KubeStellar, Argo Workflows, KubeVirt, OTel Collector aggregator, Loki, Prometheus.
2. **VMs** — KubeVirt-managed VMs on the ghost. Flatcar or Bluefin, bootc- or ignition-provisioned.
3. **Clients** — laptops and homelab machines enrolled via `knuckle`. Not k8s nodes.

Anything that maps laptops to k8s nodes is wrong.

## Tooling Decisions

- **Justfile-first.** Prefer `just <recipe>` over raw shell scripts. All automation recipes live in the justfile.
- **k8s node labels** replace config registry files. Use labels, not files on disk, for node identity and role.
- **BuildStream is Apache (not CNCF).** Documented exception — it's the build system for bootc images.

## p0 Use Case

Bluefin contributor `ujust report` loop: a contributor runs `ujust report`, the report gist is consumed by a Hive agent, the agent opens a well-formed issue with diagnostics attached, and the fix PR references that issue.

## Workflow

1. Read the justfile first — most answers are there.
2. Agent-made PRs must link to their issue with `Closes #N`.
3. Test locally before opening a PR (where feasible).
4. Do not introduce Helm charts, Tekton pipelines, or laptop-as-k8s-node patterns.
