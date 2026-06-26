#!/bin/bash
# pci-hardware-diag.sh — Diagnose PCI/GPU/power issues after GPU swap
# Run on hierophant (the KVM host), NOT inside a VM.
# Output: JSON file at /tmp/pci-diag-<timestamp>.json
# Usage: sudo bash scripts/pci-hardware-diag.sh

set -euo pipefail

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OUTFILE="/tmp/pci-diag-$(date +%Y%m%d-%H%M%S).json"
KUBECTL="${KUBECTL:-/home/k8s/kube/kubectl}"
export KUBECONFIG="${KUBECONFIG:-/home/k8s/kube/config/kubeconfig}"

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
json_str()  { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1" 2>/dev/null || echo '"'"$1"'"'; }
json_num()  { echo "${1:-0}"; }
cmd_out()   { "$@" 2>/dev/null || echo ""; }
cmd_lines() { mapfile -t arr < <("$@" 2>/dev/null || true); printf '%s\n' "${arr[@]+"${arr[@]}"}"; }

echo "=== PCI/Hardware Diagnostics ==="
echo "Output: $OUTFILE"
echo "Timestamp: $TIMESTAMP"
echo ""

# ─────────────────────────────────────────────────────────────
# 1. GPU info — collected from inside inference-0 via kubectl exec
# ─────────────────────────────────────────────────────────────
# The V100 is passed through via VFIO to the inference-0 VM. nvidia-smi on the
# KVM host fails because the GPU is owned by vfio-pci, not the nvidia driver.
# We find a running pod on inference-0 that has nvidia-smi and exec into it.
echo "[1/8] Collecting GPU state (via kubectl exec on inference-0)..."

GPU_NODE="inference-0"
GPU_IN_VM_POD=""
GPU_SOURCE="none"

# Try pods in priority order: dcgm-exporter → device-plugin → any pod with nvidia in name
for ns_pod in \
    "gpu-operator/nvidia-dcgm-exporter" \
    "gpu-operator/nvidia-device-plugin-daemonset" \
    "gpu-operator/gpu-feature-discovery"; do
    ns="${ns_pod%%/*}"
    name_prefix="${ns_pod##*/}"
    pod=$($KUBECTL get pods -n "$ns" -o wide --no-headers 2>/dev/null \
          | grep "$GPU_NODE" | grep "Running" | grep "$name_prefix" \
          | awk '{print $1}' | head -1 || true)
    if [[ -n "$pod" ]]; then
        # Verify nvidia-smi is present
        if $KUBECTL exec -n "$ns" "$pod" --request-timeout=10s -- \
               sh -c "command -v nvidia-smi" >/dev/null 2>&1; then
            GPU_IN_VM_POD="$ns/$pod"
            GPU_SOURCE="$ns_pod on $GPU_NODE"
            break
        fi
    fi
done

# Helper: run nvidia-smi query inside the inference pod
nsmi() {
    local ns pod query
    ns="${GPU_IN_VM_POD%%/*}"
    pod="${GPU_IN_VM_POD##*/}"
    query="$1"
    if [[ -z "$pod" ]]; then echo ""; return; fi
    $KUBECTL exec -n "$ns" "$pod" --request-timeout=15s -- \
        nvidia-smi --query-gpu="$query" --format=csv,noheader 2>/dev/null \
        | head -1 | tr -d ' ' || echo ""
}

if [[ -n "$GPU_IN_VM_POD" ]]; then
    echo "  Using pod: $GPU_SOURCE"
    GPU_NAME=$(nsmi "name")
    GPU_TEMP=$(nsmi "temperature.gpu")
    GPU_POWER_DRAW=$(nsmi "power.draw" | tr -d 'W')
    GPU_POWER_LIMIT=$(nsmi "power.limit" | tr -d 'W')
    GPU_PSTATE=$(nsmi "pstate")
    GPU_PERF_STATE=$(nsmi "clocks_throttle_reasons.active")
    GPU_MEM_USED=$(nsmi "memory.used" | tr -d 'MiB')
    GPU_MEM_TOTAL=$(nsmi "memory.total" | tr -d 'MiB')
    GPU_ECC_SBE=$(nsmi "ecc.errors.corrected.volatile.total")
    GPU_ECC_DBE=$(nsmi "ecc.errors.uncorrected.volatile.total")
    GPU_PCIE_GEN=$(nsmi "pcie.link.gen.current")
    GPU_PCIE_WIDTH=$(nsmi "pcie.link.width.current")
    GPU_PCIE_GEN_MAX=$(nsmi "pcie.link.gen.max")
    GPU_PCIE_WIDTH_MAX=$(nsmi "pcie.link.width.max")
    GPU_THROTTLE=$(nsmi "clocks_throttle_reasons.hw_thermal_slowdown")
else
    echo "  WARNING: No suitable pod found on $GPU_NODE — GPU metrics unavailable"
    echo "  (GPU operator may not be installed yet, or no pod has nvidia-smi)"
    GPU_NAME="" GPU_TEMP="" GPU_POWER_DRAW="" GPU_POWER_LIMIT="" GPU_PSTATE=""
    GPU_PERF_STATE="" GPU_MEM_USED="" GPU_MEM_TOTAL="" GPU_ECC_SBE="" GPU_ECC_DBE=""
    GPU_PCIE_GEN="" GPU_PCIE_WIDTH="" GPU_PCIE_GEN_MAX="" GPU_PCIE_WIDTH_MAX=""
    GPU_THROTTLE=""
fi
export GPU_SOURCE

# ─────────────────────────────────────────────────────────────
# 2. PCIe AER (Advanced Error Reporting) — from kernel ring buffer
# ─────────────────────────────────────────────────────────────
echo "[2/8] Collecting PCIe AER errors..."
AER_CORRECTED=$(dmesg 2>/dev/null | grep -c "Corrected error" || echo 0)
AER_UNCORRECTED=$(dmesg 2>/dev/null | grep -c "Uncorrected.*error\|AER.*error" || echo 0)
AER_RESET=$(dmesg 2>/dev/null | grep -c "PCIe Bus Error\|device reset\|slot reset" || echo 0)
AER_RECENT=$(dmesg --since="1 hour ago" 2>/dev/null | grep -E "AER|PCIe Bus Error|device reset|nmi_handle|edac" | tail -20 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")

# ─────────────────────────────────────────────────────────────
# 3. PCIe topology — identify which devices share root complexes
# ─────────────────────────────────────────────────────────────
echo "[3/8] Collecting PCIe topology..."
# NOTE: lspci -tv probes every device config space — hangs if a PCIe device (e.g. V100)
# is not responding. Use a 10-second timeout; a hang IS diagnostic evidence of PCIe issues.
PCIE_TREE=$(timeout 10 lspci -tv 2>/dev/null | head -60 || echo "TIMEOUT — lspci -tv hung (possible PCIe device not responding)")
if echo "$PCIE_TREE" | grep -q TIMEOUT; then
    echo "  WARNING: lspci -tv timed out — this indicates a PCIe device is not responding to config reads"
fi
# Use plain 'lspci' (no tree walk) for slot identification — much faster
GPU_SLOT=$(timeout 5 lspci 2>/dev/null | grep -i "nvidia\|tesla\|v100" | head -5 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
NVME_SLOT=$(timeout 5 lspci 2>/dev/null | grep -i "nvme\|non-volatile" | head -5 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
NET_SLOT=$(timeout 5 lspci 2>/dev/null | grep -i "ethernet\|network" | head -5 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")

# Check if GPU and NVMe/Net are on same root port (PCIe root complex = first 2 hex digits).
# Target the compute GPU (V100 = "3D controller" or "GV100\|Tesla") not the display GPU.
GPU_ROOT=$(timeout 5 lspci 2>/dev/null | grep -i "3D controller.*nvidia\|GV100\|Tesla" | head -1 | cut -d: -f1 | cut -c1-2)
# Fallback: if no compute GPU found, try any NVIDIA device
[[ -z "$GPU_ROOT" ]] && GPU_ROOT=$(timeout 5 lspci 2>/dev/null | grep -i "nvidia" | grep -v "VGA\|Audio\|High Definition" | head -1 | cut -d: -f1 | cut -c1-2)
NVME_ROOT=$(timeout 5 lspci 2>/dev/null | grep -i "nvme" | head -1 | cut -d: -f1 | cut -c1-2)
GPU_SHARES_ROOT_WITH_NVME="false"
[[ "$GPU_ROOT" == "$NVME_ROOT" && -n "$GPU_ROOT" ]] && GPU_SHARES_ROOT_WITH_NVME="true"

# ─────────────────────────────────────────────────────────────
# 4. CPU thermal and power state
# ─────────────────────────────────────────────────────────────
echo "[4/8] Collecting CPU thermal state..."
CPU_FREQ_MAX=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo 0)
CPU_FREQ_CUR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
CPU_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
CPU_TEMP=$(sensors 2>/dev/null | grep -E "Core 0|Package" | head -3 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
# Throttle check: compare max vs current frequency
CPU_THROTTLE_PCT=0
if [[ "$CPU_FREQ_MAX" -gt 0 && "$CPU_FREQ_CUR" -gt 0 ]]; then
    CPU_THROTTLE_PCT=$(python3 -c "print(round((1 - $CPU_FREQ_CUR/$CPU_FREQ_MAX)*100, 1))" 2>/dev/null || echo 0)
fi

# ─────────────────────────────────────────────────────────────
# 5. VM CPU steal time via libvirt
# ─────────────────────────────────────────────────────────────
echo "[5/8] Collecting VM CPU steal..."
VM_CPU_STATS=$(virsh list --all 2>/dev/null | grep running | awk '{print $2}' | while read vm; do
    stats=$(virsh domstats --cpu-total "$vm" 2>/dev/null | grep cpu.time | awk -F= '{print $2}')
    vcpus=$(virsh dominfo "$vm" 2>/dev/null | grep "CPU(s)" | awk '{print $2}')
    echo "{\"vm\": \"$vm\", \"cpu_time_ns\": ${stats:-0}, \"vcpus\": ${vcpus:-0}}"
done | python3 -c "import sys,json; print(json.dumps([json.loads(l) for l in sys.stdin]))" 2>/dev/null || echo "[]")

# ─────────────────────────────────────────────────────────────
# 6. Power supply / system power (IPMI if available)
# ─────────────────────────────────────────────────────────────
echo "[6/8] Collecting power/IPMI data..."
IPMI_POWER=$(ipmitool dcmi power reading 2>/dev/null | grep "Instantaneous" | awk '{print $4}' || echo "unavailable")
IPMI_TEMPS=$(ipmitool sdr type Temperature 2>/dev/null | head -10 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")

# ─────────────────────────────────────────────────────────────
# 7. Kubernetes control plane health (if accessible)
# ─────────────────────────────────────────────────────────────
echo "[7/8] Collecting Kubernetes control plane state..."
K8S_NODE_CPU=$(${KUBECTL} top nodes --no-headers 2>/dev/null | python3 -c "
import sys, json
rows = []
for line in sys.stdin:
    parts = line.split()
    if len(parts) >= 4:
        rows.append({'node': parts[0], 'cpu_cores': parts[1], 'cpu_pct': parts[2], 'mem_bytes': parts[3], 'mem_pct': parts[4] if len(parts) > 4 else ''})
print(json.dumps(rows))
" 2>/dev/null || echo "[]")

CTRL_RESTARTS=$(${KUBECTL} get pods -n kube-system -o json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
rows = []
for p in d.get('items', []):
    name = p['metadata']['name']
    for cs in p['status'].get('containerStatuses', []):
        if cs.get('restartCount', 0) > 0:
            rows.append({'pod': name, 'container': cs['name'], 'restarts': cs['restartCount']})
print(json.dumps(rows))
" 2>/dev/null || echo "[]")

ETCD_SLOW=$(${KUBECTL} logs -n kube-system \
    $(${KUBECTL} get pods -n kube-system -l component=etcd -o name 2>/dev/null | head -1 | sed 's|pod/||') \
    --since=10m 2>/dev/null | grep -c "slow fdatasync\|took too long\|overloaded" || echo 0)

# ─────────────────────────────────────────────────────────────
# 8. Memory / huge pages / NUMA
# ─────────────────────────────────────────────────────────────
echo "[8/8] Collecting memory/NUMA data..."
MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_FREE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
NUMA_NODES=$(numactl --hardware 2>/dev/null | grep "available:" | head -1 || echo "unavailable")
GPU_NUMA=$(timeout 10 nvidia-smi topo -m 2>/dev/null | head -20 || echo "unavailable")
# Export ALL variables for Python to read via os.environ.get().
# Inline bash $VAR expansion in Python heredocs breaks on empty, multi-line,
# or quoted values (common when GPU PCIe is degraded). This approach is safe
# for any content.
export TIMESTAMP GPU_NAME GPU_TEMP GPU_POWER_DRAW GPU_POWER_LIMIT GPU_PSTATE GPU_SOURCE
export GPU_PERF_STATE GPU_THROTTLE GPU_MEM_USED GPU_MEM_TOTAL
export GPU_ECC_SBE GPU_ECC_DBE GPU_PCIE_GEN GPU_PCIE_GEN_MAX
export GPU_PCIE_WIDTH GPU_PCIE_WIDTH_MAX
export AER_CORRECTED AER_UNCORRECTED AER_RESET AER_RECENT
export GPU_SLOT NVME_SLOT NET_SLOT GPU_SHARES_ROOT_WITH_NVME GPU_ROOT NVME_ROOT
export CPU_GOV CPU_FREQ_MAX CPU_FREQ_CUR CPU_THROTTLE_PCT CPU_TEMP
export IPMI_POWER IPMI_TEMPS VM_CPU_STATS
export K8S_NODE_CPU CTRL_RESTARTS ETCD_SLOW
export MEM_TOTAL MEM_FREE NUMA_NODES GPU_NUMA OUTFILE

# ─────────────────────────────────────────────────────────────
# Assemble JSON
# ─────────────────────────────────────────────────────────────
python3 - <<'PYEOF'
import json, os

def e(k, default=""):
    return os.environ.get(k, default)

def ei(k):
    try: return int(e(k) or 0)
    except: return 0

def ef(k):
    try: return float(e(k) or 0)
    except: return 0.0

def ej(k, default=None):
    try: return json.loads(e(k) or "null")
    except: return default if default is not None else e(k)

gen     = e("GPU_PCIE_GEN")
gen_max = e("GPU_PCIE_GEN_MAX")
wid     = e("GPU_PCIE_WIDTH")
wid_max = e("GPU_PCIE_WIDTH_MAX")
throttle = e("GPU_THROTTLE")
aer_corr = ei("AER_CORRECTED")
aer_uncorr = ei("AER_UNCORRECTED")
cpu_thr  = ef("CPU_THROTTLE_PCT")
etcd_slow = ei("ETCD_SLOW")

data = {
    "timestamp": e("TIMESTAMP"),
    "host": e("HOSTNAME", os.uname().nodename),
    "gpu": {
        "metrics_source":        e("GPU_SOURCE", "host-nvidia-smi"),
        "name":                  e("GPU_NAME"),
        "temperature_c":         e("GPU_TEMP"),
        "power_draw_w":          e("GPU_POWER_DRAW"),
        "power_limit_w":         e("GPU_POWER_LIMIT"),
        "performance_state":     e("GPU_PSTATE"),
        "throttle_reasons_active": e("GPU_PERF_STATE"),
        "hw_thermal_slowdown":   e("GPU_THROTTLE"),
        "memory_used_mib":       e("GPU_MEM_USED"),
        "memory_total_mib":      e("GPU_MEM_TOTAL"),
        "ecc_corrected":         e("GPU_ECC_SBE"),
        "ecc_uncorrected":       e("GPU_ECC_DBE"),
        "pcie_gen_current":      gen,
        "pcie_gen_max":          gen_max,
        "pcie_width_current":    wid,
        "pcie_width_max":        wid_max,
    },
    "pcie": {
        "aer_corrected_total":          aer_corr,
        "aer_uncorrected_total":        aer_uncorr,
        "reset_events_total":           ei("AER_RESET"),
        "recent_errors":                ej("AER_RECENT", []),
        "gpu_pcie_slot":                ej("GPU_SLOT", []),
        "nvme_pcie_slot":               ej("NVME_SLOT", []),
        "network_pcie_slot":            ej("NET_SLOT", []),
        "gpu_shares_root_complex_with_nvme": e("GPU_SHARES_ROOT_WITH_NVME") == "true",
        "gpu_root_bus":                 e("GPU_ROOT"),
        "nvme_root_bus":                e("NVME_ROOT"),
    },
    "cpu": {
        "governor":        e("CPU_GOV"),
        "freq_max_khz":    ei("CPU_FREQ_MAX"),
        "freq_current_khz": ei("CPU_FREQ_CUR"),
        "throttle_pct":    cpu_thr,
        "thermal_sensors": ej("CPU_TEMP", []),
    },
    "power": {
        "ipmi_instantaneous_watts": e("IPMI_POWER"),
        "ipmi_temps":               ej("IPMI_TEMPS", []),
    },
    "memory": {
        "total_kb":          ei("MEM_TOTAL"),
        "available_kb":      ei("MEM_FREE"),
        "numa_info":         e("NUMA_NODES"),
        "gpu_numa_topology": e("GPU_NUMA"),
    },
    "vms": {
        "cpu_stats": ej("VM_CPU_STATS", []),
    },
    "kubernetes": {
        "node_cpu":                 ej("K8S_NODE_CPU", []),
        "high_restart_containers":  ej("CTRL_RESTARTS", []),
        "etcd_slow_ops_last_10m":   etcd_slow,
    },
    "diagnosis": {
        "pcie_gen_downgraded":   bool(gen and gen_max and gen != gen_max),
        "pcie_width_downgraded": bool(wid and wid_max and wid != wid_max),
        "gpu_thermal_throttling": bool(throttle and throttle not in ("", "Not Active", "0x0000000000000000")),
        "aer_errors_present":    (aer_corr + aer_uncorr) > 0,
        "cpu_freq_throttled":    cpu_thr > 5,
        "etcd_slow":             etcd_slow > 0,
    }
}

outfile = e("OUTFILE", "/tmp/pci-diag.json")
with open(outfile, "w") as f:
    json.dump(data, f, indent=2)

print(f"\nDiagnostics written to: {outfile}")
print("\n=== SUMMARY ===")
d = data["diagnosis"]
gpu = data["gpu"]
pcie = data["pcie"]
print(f"  GPU: {gpu['name']}")
print(f"  GPU temp: {gpu['temperature_c']}°C  power: {gpu['power_draw_w']}W / {gpu['power_limit_w']}W")
print(f"  PCIe: Gen{gpu['pcie_gen_current']} x{gpu['pcie_width_current']} (max: Gen{gen_max} x{wid_max})")
print(f"  AER errors: {aer_corr} corrected, {aer_uncorr} uncorrected, {ei('AER_RESET')} resets")
print(f"  GPU shares PCIe root complex with NVMe: {pcie['gpu_shares_root_complex_with_nvme']}")
print(f"  CPU throttle: {cpu_thr}%   governor: {e('CPU_GOV')}")
print(f"  IPMI power: {e('IPMI_POWER')}")
print()
if any(d.values()):
    print("⚠  FLAGS RAISED:")
    if d["pcie_gen_downgraded"]:    print(f"   ✗ PCIe link degraded to Gen{gen} (max Gen{gen_max}) — slot/cable issue")
    if d["pcie_width_downgraded"]:  print(f"   ✗ PCIe width degraded to x{wid} (max x{wid_max}) — slot/bifurcation issue")
    if d["gpu_thermal_throttling"]: print(f"   ✗ GPU thermal throttling ACTIVE — inadequate cooling in workstation chassis")
    if d["aer_errors_present"]:     print(f"   ✗ PCIe AER errors present — device resets affecting hypervisor I/O latency")
    if d["cpu_freq_throttled"]:     print(f"   ✗ CPU frequency throttled {cpu_thr}% — thermal or power limit")
    if d["etcd_slow"]:              print(f"   ✗ etcd slow operations detected — control plane I/O latency")
else:
    print("✓  No hardware flags raised")
PYEOF
