# Talos GPU Follow-Up Note

## Background
GPU Operator validator failures were traced to a path mismatch on Talos:
- Validator expects driver assets under `/run/nvidia/driver`.
- Talos exposes NVIDIA userspace under `/usr/local` (for example `/usr/local/bin/nvidia-smi` and `/usr/local/glibc/usr/lib/libnvidia-ml.so.1`).

Current mitigation uses `nvidia-talos-validation-fix` to keep:
- validation markers under `/run/nvidia/validations`
- symlinks under `/run/nvidia/driver/usr/*`

## Deferred Improvement (To Revisit)
Replace the continuous loop approach with a more event-driven design:

1. Run-on-upgrade setup:
- Add a one-shot action on GPU Operator install/upgrade to create the required `/run/nvidia/driver` mappings and validation markers.
- This can be implemented as a Helm hook Job or equivalent upgrade-time job.

2. Talos boot-time setup:
- Add Talos-side initialization (machine config/system extension/task) that recreates the same `/run/nvidia/driver` mappings after node reboot.
- Goal: keep behavior correct even when `/run` is reset.

## Why This Is Deferred
- The current loop is stable and low overhead.
- A full replacement should be validated carefully across:
  - Talos upgrades
  - node reboots
  - GPU Operator chart upgrades
  - reconciliation after pod restarts

This item is intentionally parked for later implementation.
