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
# 1. GPU info (nvidia-smi)
# ─────────────────────────────────────────────────────────────
echo "[1/8] Collecting GPU state..."
GPU_NAME=$(cmd_out nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_TEMP=$(cmd_out nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -1)
GPU_POWER_DRAW=$(cmd_out nvidia-smi --query-gpu=power.draw --format=csv,noheader | head -1 | tr -d ' W')
GPU_POWER_LIMIT=$(cmd_out nvidia-smi --query-gpu=power.limit --format=csv,noheader | head -1 | tr -d ' W')
GPU_PSTATE=$(cmd_out nvidia-smi --query-gpu=pstate --format=csv,noheader | head -1)
GPU_PERF_STATE=$(cmd_out nvidia-smi --query-gpu=clocks_throttle_reasons.active --format=csv,noheader | head -1)
GPU_MEM_USED=$(cmd_out nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1 | tr -d ' MiB')
GPU_MEM_TOTAL=$(cmd_out nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1 | tr -d ' MiB')
GPU_ECC_SBE=$(cmd_out nvidia-smi --query-gpu=ecc.errors.corrected.volatile.total --format=csv,noheader | head -1)
GPU_ECC_DBE=$(cmd_out nvidia-smi --query-gpu=ecc.errors.uncorrected.volatile.total --format=csv,noheader | head -1)
GPU_PCIE_GEN=$(cmd_out nvidia-smi --query-gpu=pcie.link.gen.current --format=csv,noheader | head -1)
GPU_PCIE_WIDTH=$(cmd_out nvidia-smi --query-gpu=pcie.link.width.current --format=csv,noheader | head -1)
GPU_PCIE_GEN_MAX=$(cmd_out nvidia-smi --query-gpu=pcie.link.gen.max --format=csv,noheader | head -1)
GPU_PCIE_WIDTH_MAX=$(cmd_out nvidia-smi --query-gpu=pcie.link.width.max --format=csv,noheader | head -1)
GPU_THROTTLE=$(cmd_out nvidia-smi --query-gpu=clocks_throttle_reasons.hw_thermal_slowdown \
    --format=csv,noheader | head -1)

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
PCIE_TREE=$(lspci -tv 2>/dev/null | head -60)
GPU_SLOT=$(lspci 2>/dev/null | grep -i "nvidia\|tesla\|v100" | head -5 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
NVME_SLOT=$(lspci 2>/dev/null | grep -i "nvme\|non-volatile" | head -5 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
NET_SLOT=$(lspci 2>/dev/null | grep -i "ethernet\|network" | head -5 | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")

# Check if GPU and NVMe/Net are on same root port (PCIe root complex = first 2 hex digits)
GPU_ROOT=$(lspci 2>/dev/null | grep -i "nvidia\|tesla\|v100" | head -1 | cut -d: -f1 | cut -c1-2)
NVME_ROOT=$(lspci 2>/dev/null | grep -i "nvme" | head -1 | cut -d: -f1 | cut -c1-2)
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
GPU_NUMA=$(nvidia-smi topo -m 2>/dev/null | head -20 || echo "unavailable")

# ─────────────────────────────────────────────────────────────
# Assemble JSON
# ─────────────────────────────────────────────────────────────
python3 - <<PYEOF
import json, os

data = {
    "timestamp": "$TIMESTAMP",
    "host": "$(hostname)",
    "gpu": {
        "name": "$GPU_NAME",
        "temperature_c": "$GPU_TEMP",
        "power_draw_w": "$GPU_POWER_DRAW",
        "power_limit_w": "$GPU_POWER_LIMIT",
        "performance_state": "$GPU_PSTATE",
        "throttle_reasons_active": "$GPU_PERF_STATE",
        "hw_thermal_slowdown": "$GPU_THROTTLE",
        "memory_used_mib": "$GPU_MEM_USED",
        "memory_total_mib": "$GPU_MEM_TOTAL",
        "ecc_corrected": "$GPU_ECC_SBE",
        "ecc_uncorrected": "$GPU_ECC_DBE",
        "pcie_gen_current": "$GPU_PCIE_GEN",
        "pcie_gen_max": "$GPU_PCIE_GEN_MAX",
        "pcie_width_current": "$GPU_PCIE_WIDTH",
        "pcie_width_max": "$GPU_PCIE_WIDTH_MAX"
    },
    "pcie": {
        "aer_corrected_total": $AER_CORRECTED,
        "aer_uncorrected_total": $AER_UNCORRECTED,
        "reset_events_total": $AER_RESET,
        "recent_errors": $AER_RECENT,
        "gpu_pcie_slot": $GPU_SLOT,
        "nvme_pcie_slot": $NVME_SLOT,
        "network_pcie_slot": $NET_SLOT,
        "gpu_shares_root_complex_with_nvme": $GPU_SHARES_ROOT_WITH_NVME,
        "gpu_root_bus": "$GPU_ROOT",
        "nvme_root_bus": "$NVME_ROOT"
    },
    "cpu": {
        "governor": "$CPU_GOV",
        "freq_max_khz": $CPU_FREQ_MAX,
        "freq_current_khz": $CPU_FREQ_CUR,
        "throttle_pct": $CPU_THROTTLE_PCT,
        "thermal_sensors": $CPU_TEMP
    },
    "power": {
        "ipmi_instantaneous_watts": "$IPMI_POWER",
        "ipmi_temps": $IPMI_TEMPS
    },
    "memory": {
        "total_kb": $MEM_TOTAL,
        "available_kb": $MEM_FREE,
        "numa_info": $(json.dumps("$NUMA_NODES")),
        "gpu_numa_topology": $(json.dumps("$GPU_NUMA"))
    },
    "vms": {
        "cpu_stats": $VM_CPU_STATS
    },
    "kubernetes": {
        "node_cpu": $K8S_NODE_CPU,
        "high_restart_containers": $CTRL_RESTARTS,
        "etcd_slow_ops_last_10m": $ETCD_SLOW
    },
    "diagnosis": {
        "pcie_gen_downgraded": ("$GPU_PCIE_GEN" != "$GPU_PCIE_GEN_MAX" and "$GPU_PCIE_GEN" != "" and "$GPU_PCIE_GEN_MAX" != ""),
        "pcie_width_downgraded": ("$GPU_PCIE_WIDTH" != "$GPU_PCIE_WIDTH_MAX" and "$GPU_PCIE_WIDTH" != "" and "$GPU_PCIE_WIDTH_MAX" != ""),
        "gpu_thermal_throttling": ("$GPU_THROTTLE" not in ("", "Not Active", "0x0000000000000000")),
        "aer_errors_present": ($AER_CORRECTED + $AER_UNCORRECTED > 0),
        "cpu_freq_throttled": ($CPU_THROTTLE_PCT > 5),
        "etcd_slow": ($ETCD_SLOW > 0)
    }
}

outfile = "$OUTFILE"
with open(outfile, "w") as f:
    json.dump(data, f, indent=2)

print(f"\nDiagnostics written to: {outfile}")
print("\n=== SUMMARY ===")
d = data["diagnosis"]
gpu = data["gpu"]
pcie = data["pcie"]
print(f"  GPU: {data['gpu']['name']}")
print(f"  GPU temp: {gpu['temperature_c']}°C  power: {gpu['power_draw_w']}W / {gpu['power_limit_w']}W")
print(f"  PCIe: Gen{gpu['pcie_gen_current']} x{gpu['pcie_width_current']} (max: Gen{gpu['pcie_gen_max']} x{gpu['pcie_width_max']})")
print(f"  AER errors: {pcie['aer_corrected_total']} corrected, {pcie['aer_uncorrected_total']} uncorrected, {pcie['reset_events_total']} resets")
print(f"  GPU shares PCIe root complex with NVMe: {pcie['gpu_shares_root_complex_with_nvme']}")
print(f"  CPU throttle: {data['cpu']['throttle_pct']}%   governor: {data['cpu']['governor']}")
print(f"  IPMI power: {data['power']['ipmi_instantaneous_watts']}")
print()
if any(d.values()):
    print("⚠  FLAGS RAISED:")
    if d["pcie_gen_downgraded"]:   print("   ✗ PCIe link degraded to Gen" + gpu["pcie_gen_current"] + " (max Gen" + gpu["pcie_gen_max"] + ") — slot/cable issue")
    if d["pcie_width_downgraded"]: print("   ✗ PCIe width degraded to x" + gpu["pcie_width_current"] + " (max x" + gpu["pcie_width_max"] + ") — slot/bifurcation issue")
    if d["gpu_thermal_throttling"]: print("   ✗ GPU thermal throttling ACTIVE — inadequate cooling in workstation chassis")
    if d["aer_errors_present"]:    print("   ✗ PCIe AER errors present — device resets affecting hypervisor I/O latency")
    if d["cpu_freq_throttled"]:    print("   ✗ CPU frequency throttled " + str(data["cpu"]["throttle_pct"]) + "% — thermal or power limit")
    if d["etcd_slow"]:             print("   ✗ etcd slow operations detected — control plane I/O latency")
else:
    print("✓  No hardware flags raised")
PYEOF
