# Kubernetes Cluster Configuration Details

This document provides a detailed overview of the Kubernetes cluster virtual machines,
CPU/NUMA pinning, storage layout, and network configuration.

Setup scripts: `../kubernetes-setup/new-setup-single/`

## 1. Cluster Overview

- **Host Machine**: `hierophant` (dual-socket Intel Xeon E5-2680 v4, 56 logical CPUs, 263GB RAM)
- **Virtualization**: KVM / Libvirt (QEMU)
- **Operating System**: Talos Linux v1.12.4
- **Installation Root**: `/mnt/hegemon-share/share/code/kubernetes-setup`
- **GPU**: NVIDIA Tesla V100 (GV100GL PG500-216) — PCIe passthrough to inference-0

## 2. CPU & NUMA Topology

### 2.1 Host CPU Layout

```
Socket 0 (NUMA 0): CPUs 0-13, 28-41  — GPU (V100) + SAS HBA (LSI SAS2308)
Socket 1 (NUMA 1): CPUs 14-27, 42-55 — NVMe drives (4× Netac NV3000)
```

### 2.2 VM CPU Pinning

Total: 50 vCPUs allocated, 6 reserved for host.

| VM | vCPUs | cpuset | NUMA | Rationale |
| :--- | :---: | :--- | :---: | :--- |
| **inference-0** | 14 | `0-13` | 0 | GPU on NUMA 0; GPU inference is GPU-bound |
| **control-0** | 4 | `28-31` | 0 | etcd + API server; 4 vCPU sufficient for <10 nodes |
| **control-1** | 4 | `32-35` | 0 | |
| **control-2** | 4 | `36-39` | 0 | |
| **worker-0** | 8 | `14-17,42-45` | 1 | NVMe drives on NUMA 1; Ceph OSD latency-critical |
| **worker-1** | 8 | `18-21,46-49` | 1 | |
| **worker-2** | 8 | `22-25,50-53` | 1 | |
| **Host reserved** | — | `40-41` (NUMA 0), `26-27,54-55` (NUMA 1) | both | QEMU emulator threads, NVMe IRQs, kernel IO |

### 2.3 IO Threads

Worker VMs have 2 dedicated IO threads each to offload disk IO from vCPU threads:
- **iothread 1**: SATA HDD OSD data disks
- **iothread 2**: NVMe BlueStore DB + NVMe fast-tier OSD disks

## 3. Network Configuration

Dual-homed network on all nodes:
- **eth0**: Internal management and Talos API traffic
- **eth1**: Application traffic and External LoadBalancer access

### 3.1 Virtual Networks & Bridges

| Network Name | Bridge | Subnet | Gateway | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **talos-nat** | `talos-bridge` | `10.0.0.0/24` | `10.0.0.1` | Talos Management & Control Plane |
| **lb-net** | `br-app` | `172.20.0.0/16` | `172.20.0.1` | Application Services (VLAN 20) |

### 3.2 Host Interfaces (hierophant)

- **enp5s0**: `192.168.1.101/24` — Physical Management Uplink
- **eno1**: Physical interface for Application traffic (VLAN 20 tagged)
- **br-app**: `172.20.0.1/16` — Bridge for Application traffic
- **talos-bridge**: `10.0.0.1/24` — Bridge for internal VM management

## 4. Virtual Machine Inventory

### 4.1 Control Plane Nodes (3 nodes)

4 vCPUs, 16GB RAM each. Pinned to NUMA 0 (CPUs 28-39).

| VM Name | IP Address | MAC (talos-nat) | MAC (lb-net) | OS Disk |
| :--- | :--- | :--- | :--- | :--- |
| **control-0** | `10.0.0.200` | `6A:69:11:AA:00:A1` | `6A:69:11:AA:10:A1` | nvme-362996-p1 (30GB) |
| **control-1** | `10.0.0.201` | `6A:69:11:AA:00:A2` | `6A:69:11:AA:10:A2` | nvme-362830-p1 (30GB) |
| **control-2** | `10.0.0.202` | `6A:69:11:AA:00:A3` | `6A:69:11:AA:10:A3` | nvme-362984-p1 (30GB) |

Each control-plane node is on a separate physical NVMe drive for HA.
Single-drive failure loses 1 of 3 etcd members — quorum maintained.

### 4.2 Worker Nodes (3 nodes)

8 vCPUs, 28GB RAM each. Pinned to NUMA 1 (NVMe drives on same NUMA node).

| VM Name | IP Address | MAC (talos-nat) | MAC (lb-net) |
| :--- | :--- | :--- | :--- |
| **worker-0** | `10.0.0.110` | `6A:69:11:AA:00:A4` | `6A:69:11:AA:10:A4` |
| **worker-1** | `10.0.0.111` | `6A:69:11:AA:00:A5` | `6A:69:11:AA:10:A5` |
| **worker-2** | `10.0.0.112` | `6A:69:11:AA:00:A6` | `6A:69:11:AA:10:A6` |

#### Worker Disk Attachments

| Device | worker-0 | worker-1 | worker-2 |
| :--- | :--- | :--- | :--- |
| **vda** (OS) | nvme-362830-p2 (30GB) | nvme-362830-p4 (30GB) | nvme-362984-p2 (30GB) |
| **vdb** (SATA OSD) | ST2000DM008-ZFL32CQR (1.8TB) | ST2000DM008-ZFL32BZX (1.8TB) | ST2000DM008-ZFL32BA2 (1.8TB) |
| **vdc** (NVMe BlueStore DB) | nvme-362830-p3 (70GB) | nvme-362830-p5 (70GB) | nvme-362984-p3 (70GB) |
| **vdd** (NVMe fast-tier OSD) | nvme-362996-p2 (195GB) | — | — |
| **vde** (SATA OSD #2) | ST2000DM008-ZFL34JEA (1.8TB) | — | — |
| **vdf** (NVMe BlueStore DB #2) | nvme-362984-p5 (70GB) | — | — |

Worker-0 carries the extra storage from the eliminated worker-3 (SATA HDD + NVMe BlueStore DB).

### 4.3 Inference Node (1 node)

14 vCPUs, 64GB RAM. Pinned to NUMA 0 (GPU on same NUMA node).
GPU passthrough via vfio-pci.

| VM Name | IP Address | MAC (talos-nat) | MAC (lb-net) | CPU Pinning |
| :--- | :--- | :--- | :--- | :--- |
| **inference-0** | `10.0.0.120` | `6A:69:11:AA:00:A8` | `6A:69:11:AA:10:A8` | `0-13` |

| Device | Disk |
| :--- | :--- |
| **vda** (OS) | nvme-362935-p1 (80GB) |
| **vdb** (Model storage) | nvme-362935-p2 (150GB) |

## 5. Storage Infrastructure

### 5.1 Physical NVMe Partitioning (4× Netac NV3000 250GB, DRAM-less)

All NVMe drives are on NUMA 1 (PCIe buses 86-8b). Gen3 x4 link.

**Drive nvme-362996** (233GB):
- p1 = 30GB — control-0 OS
- p2 = 195GB — worker-0 NVMe fast-tier OSD (vdd)

**Drive nvme-362830** (233GB):
- p1 = 30GB — control-1 OS
- p2 = 30GB — worker-0 OS
- p3 = 70GB — worker-0 BlueStore DB (vdc)
- p4 = 30GB — worker-1 OS
- p5 = 70GB — worker-1 BlueStore DB (vdc)

**Drive nvme-362984** (233GB):
- p1 = 30GB — control-2 OS
- p2 = 30GB — worker-2 OS
- p3 = 70GB — worker-2 BlueStore DB (vdc)
- p4 = 30GB — unused (former worker-3 OS)
- p5 = 70GB — worker-0 BlueStore DB #2 (vdf, for second SATA OSD)

**Drive nvme-362935** (233GB) — dedicated to inference:
- p1 = 80GB — inference-0 OS
- p2 = 150GB — inference-0 model storage (vdb)

### 5.2 SATA HDDs (4× Seagate ST2000DM008 2TB, 7200 RPM)

Connected via LSI SAS2308 HBA on NUMA 0.

| Serial | Assigned To | VM Device |
| :--- | :--- | :--- |
| ZFL32CQR | worker-0 | vdb (OSD #1) |
| ZFL32BZX | worker-1 | vdb |
| ZFL32BA2 | worker-2 | vdb |
| ZFL34JEA | worker-0 | vde (OSD #2, former worker-3) |

### 5.3 Ceph Storage Summary

- **SATA OSDs**: 4 (worker-0 ×2, worker-1 ×1, worker-2 ×1) = 7.2TB raw
- **NVMe fast-tier OSD**: 1 on worker-0 (195GB)
- **BlueStore DB**: Each SATA OSD has a dedicated 70GB NVMe DB partition
- **Replication**: 3× (usable ~2.4TB SATA + ~65GB NVMe)

## 6. Security & Isolation

- **VLAN 20**: Used on `lb-net` (application) bridge to isolate external traffic
- **NAT**: `talos-nat` is NATed through host's `enp5s0` for internet access
- **ARP**: Host-level sysctl tweaks (`arp_ignore=1`, `arp_announce=2`, `rp_filter=0`) for multi-homed VMs
- **TLS**: All RAG services use TLS with internal CA distributed via `registry-ca-cm` ConfigMap
- **GPU Isolation**: V100 detached from host PCI and passed through exclusively to inference-0 via vfio-pci
