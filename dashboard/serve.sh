#!/usr/bin/env bash
# serve.sh — Deploy the Bluespeed Ghost: Bluespeed dashboard
# Runs ON ghost (192.168.1.102) after files have been rsync'd here.
#
# Usage: bash serve.sh
# Output: nginx container serving http://192.168.1.102:8091

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

KUBECONFIG="${HOME}/.config/bluespeed/kubeconfig"
K3S="/usr/local/bin/k3s"

echo "🦖 Ghost: Bluespeed — deploying dashboard"
echo "   Dir: $SCRIPT_DIR"
echo ""

# ── Step 1: Generate exos.json from registry.yaml (if available) ─────────────
echo "→ Generating exos.json..."
REGISTRY=""
# Look for registry.yaml in common locations
for candidate in \
    "${SCRIPT_DIR}/../exos/registry.yaml" \
    "${HOME}/src/bluespeed/exos/registry.yaml" \
    "${HOME}/bluespeed/exos/registry.yaml"; do
    if [ -f "$candidate" ]; then
        REGISTRY="$(realpath "$candidate")"
        break
    fi
done

if [ -n "$REGISTRY" ]; then
    echo "  Found registry: $REGISTRY"
    python3 - "$REGISTRY" > exos.json <<'PYEOF'
import sys, json

def parse_registry(path):
    """Minimal YAML parser for the specific registry.yaml format (no PyYAML needed)."""
    try:
        import yaml
        with open(path) as f:
            data = yaml.safe_load(f)
        return data.get('exos', [])
    except ImportError:
        pass

    # Fallback: hand-parse the simple list-of-dicts YAML
    with open(path) as f:
        lines = f.readlines()

    exos = []
    current = None
    for line in lines:
        stripped = line.rstrip()
        if stripped.strip().startswith('#') or not stripped.strip():
            continue
        # Detect new list item
        if stripped.lstrip().startswith('- '):
            if current is not None:
                exos.append(current)
            current = {}
            kv = stripped.lstrip()[2:].strip()
            if ':' in kv:
                k, _, v = kv.partition(':')
                current[k.strip()] = v.strip().strip('"')
        elif ':' in stripped and current is not None:
            indent = len(stripped) - len(stripped.lstrip())
            if indent > 0:
                k, _, v = stripped.strip().partition(':')
                v = v.strip().strip('"')
                try:
                    v = int(v)
                except ValueError:
                    pass
                current[k.strip()] = v
    if current is not None:
        exos.append(current)
    return exos

exos = parse_registry(sys.argv[1])
print(json.dumps(exos, indent=2))
PYEOF
    echo "  ✓ exos.json generated ($(python3 -c "import json; d=json.load(open('exos.json')); print(len(d))") entries)"
else
    echo "  ⚠ registry.yaml not found — using bundled exos.json"
fi

# ── Step 2: Generate stats.json (disk, uptime, k3s snapshot) ──────────────────
echo "→ Generating stats.json..."
python3 - <<PYEOF
import json, subprocess, os, datetime

stats = {
    "generated": datetime.datetime.now().isoformat(timespec='seconds'),
}

# ── Disk /var ──────────────────────────────────────────────────────────────────
try:
    out = subprocess.check_output(['df', '--output=used,avail,pcent', '/var'],
                                  text=True).splitlines()
    # Header on line 0, data on line 1: "Used    Avail Use%"
    parts = out[1].split()
    used_kb  = int(parts[0])
    avail_kb = int(parts[1])
    pct_str  = parts[2].rstrip('%')
    total_kb = used_kb + avail_kb
    stats['disk_var_used_pct']   = int(pct_str)
    stats['disk_var_used_gb']    = round(used_kb  / (1024 * 1024), 1)
    stats['disk_var_total_gb']   = round(total_kb / (1024 * 1024), 1)
    stats['disk_var_used_label'] = f"{stats['disk_var_used_gb']} TiB" if stats['disk_var_used_gb'] > 1000 else f"{stats['disk_var_used_gb']} GiB"
    print(f"  disk /var: {pct_str}% ({stats['disk_var_used_gb']} GiB used / {stats['disk_var_total_gb']} GiB total)")
except Exception as e:
    print(f"  ⚠ disk stat failed: {e}")

# ── Uptime ─────────────────────────────────────────────────────────────────────
try:
    with open('/proc/uptime') as f:
        uptime_sec = int(float(f.read().split()[0]))
    stats['uptime_seconds'] = uptime_sec

    # Boot time = now - uptime
    boot_dt = datetime.datetime.now() - datetime.timedelta(seconds=uptime_sec)
    stats['boot_time'] = boot_dt.strftime('%Y-%m-%d %H:%M')
    d = uptime_sec // 86400
    h = (uptime_sec % 86400) // 3600
    m = (uptime_sec % 3600) // 60
    print(f"  uptime: {d}d {h}h {m}m")
except Exception as e:
    print(f"  ⚠ uptime failed: {e}")

# ── k3s nodes ─────────────────────────────────────────────────────────────────
kubeconfig = os.path.expanduser('~/.config/bluespeed/kubeconfig')
k3s_bin    = '/usr/local/bin/k3s'
k3s_nodes  = []
pods_running = 0
pods_total   = 0
k3s_version  = ''

try:
    env = dict(os.environ, KUBECONFIG=kubeconfig)
    # Get nodes as JSON
    out = subprocess.check_output(
        [k3s_bin, 'kubectl', 'get', 'nodes', '-o', 'json'],
        env=env, text=True, timeout=10)
    import json as _json
    nl = _json.loads(out)
    for item in nl.get('items', []):
        name   = item['metadata']['name']
        roles  = [k.replace('node-role.kubernetes.io/', '')
                  for k in item['metadata'].get('labels', {})
                  if k.startswith('node-role.kubernetes.io/')]
        conds  = item.get('status', {}).get('conditions', [])
        status = next((c['type'] for c in conds if c['type'] == 'Ready' and c['status'] == 'True'), 'NotReady')
        info   = item.get('status', {}).get('nodeInfo', {})
        addrs  = item.get('status', {}).get('addresses', [])
        ip     = next((a['address'] for a in addrs if a['type'] == 'InternalIP'), '')
        # OS: shorten Flatcar string
        os_img = info.get('osImage', '')
        if 'Flatcar' in os_img:
            os_img = 'Flatcar ' + info.get('kernelVersion', '').split('-')[0]
        k3s_version = info.get('kubeletVersion', '')
        k3s_nodes.append({
            'name':    name,
            'status':  status,
            'roles':   roles,
            'os':      os_img,
            'ip':      ip,
            'version': k3s_version,
        })
    print(f"  k3s nodes: {[n['name'] for n in k3s_nodes]}")
except Exception as e:
    print(f"  ⚠ k3s nodes failed: {e}")

try:
    env = dict(os.environ, KUBECONFIG=kubeconfig)
    out = subprocess.check_output(
        [k3s_bin, 'kubectl', 'get', 'pods', '-A', '--no-headers'],
        env=env, text=True, timeout=10)
    lines = [l for l in out.splitlines() if l.strip()]
    pods_total   = len(lines)
    pods_running = sum(1 for l in lines if 'Running' in l)
    print(f"  pods: {pods_running}/{pods_total} running")
except Exception as e:
    print(f"  ⚠ pods failed: {e}")

stats['k3s_nodes']    = k3s_nodes
stats['pods_running'] = pods_running
stats['pods_total']   = pods_total
stats['k3s_version']  = k3s_version

with open('stats.json', 'w') as f:
    json.dump(stats, f, indent=2)
print('  ✓ stats.json written')
PYEOF

# ── Step 3: Start nginx container ─────────────────────────────────────────────
echo ""
echo "→ Starting nginx dashboard container..."
podman run -d \
    --name bluespeed-dashboard \
    --replace \
    --network=host \
    -v "${SCRIPT_DIR}:/usr/share/nginx/html:ro,Z" \
    -v "${SCRIPT_DIR}/nginx.conf:/etc/nginx/conf.d/default.conf:ro,Z" \
    docker.io/library/nginx:alpine \
    nginx -g 'daemon off;' 2>&1

# Wait for it to start
sleep 2

# ── Step 4: Verify ────────────────────────────────────────────────────────────
echo ""
echo "→ Verifying..."
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1:8091/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    TITLE_CHECK=$(curl -sf http://127.0.0.1:8091/ | grep -c 'Ghost: Bluespeed' || true)
    if [ "${TITLE_CHECK}" -ge 1 ]; then
        echo ""
        echo "✅ Ghost: Bluespeed is live!"
        echo "   http://192.168.1.102:8091"
    else
        echo "⚠ HTTP 200 but 'Ghost: Bluespeed' not found in response"
    fi
else
    echo "❌ HTTP $HTTP_CODE — check: podman logs bluespeed-dashboard"
    exit 1
fi
