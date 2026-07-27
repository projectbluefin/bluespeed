# TLS for Homelab Services — Evaluation

**Closes #36**

## Current State

Lab web UIs (KubeStellar :8090, KubeVirt Manager :30180, Argo :2746) use plain HTTP or self-signed certs requiring manual CA import on every client.

## Evaluated Approaches

### 1. cert-manager + Let's Encrypt DNS-01 ⭐ Recommended

- **Pros:** Real trusted certs, scales to all services, standard k8s pattern
- **Cons:** Requires public domain + DNS API (Cloudflare, Route53)
- **Effort:** Medium — configure cert-manager, ClusterIssuer, Ingress annotations

### 2. Tailscale HTTPS

- **Pros:** Zero config, auto Let's Encrypt certs for `*.ts.net` names
- **Cons:** Requires all clients to use Tailscale
- **Effort:** Low — `tailscale cert`

### 3. mkcert CA baked into provisioning

- **Pros:** Current approach, familiar
- **Cons:** CA tied to ghost machine, needs import on every client
- **Effort:** Low — already in use

### 4. Caddy reverse proxy

- **Pros:** Automatic ACME, single entry point for all services
- **Cons:** Adds reverse proxy complexity
- **Effort:** Medium

## Decision

Option 1 (cert-manager) for the long term, with Option 2 (Tailscale) as the lightweight fallback.
