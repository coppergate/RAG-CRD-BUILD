# Kubernetes Cluster Configuration Details

This document provides a detailed overview of the Kubernetes cluster virtual machines and network configuration, as defined in the `./new-setup` orchestration scripts.

## 1. Cluster Overview
- **Host Machine**: `hierophant`
- **Virtualization**: KVM / Libvirt
- **Operating System**: Talos Linux v1.12.4
- **Installation Root**: `/mnt/hegemon-share/share/code/kubernetes-setup`

## 2. Network Configuration

The cluster uses a dual-homed network configuration for all nodes:
- **Primary Interface (eth0)**: Internal management and Talos API traffic.
- **Secondary Interface (eth1)**: Application traffic and External LoadBalancer access.

### 2.1 Virtual Networks & Bridges

| Network Name | Bridge | Subnet | Gateway | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **talos-nat** | `talos-bridge` | `10.0.0.0/24` | `10.0.0.1` | Talos Management & Control Plane |
| **lb-net** | `br-app` | `172.20.0.0/16` | `172.20.0.1` | Application Services (VLAN 20) |

### 2.2 Host Interfaces (hierophant)
- **enp5s0**: `192.168.1.101/24` - Physical Management Uplink.
- **eno1**: Physical interface for Application traffic (VLAN 20 tagged).
- **br-app**: `172.20.0.1/16` - Bridge for Application traffic.
- **talos-bridge**: `10.0.0.1/24` - Bridge for internal VM management.

## 3. Virtual Machine Inventory

### 3.1 Control Plane Nodes
All control plane nodes run with 4 vCPUs and 8GB RAM.

| VM Name | IP Address | MAC (talos-nat) | MAC (lb-net) | Storage |
| :--- | :--- | :--- | :--- | :--- |
| **control-0** | `10.0.0.200` | `6A:69:11:AA:00:A1` | `6A:69:11:AA:10:A1` | 60GB (qcow2) |
| **control-1** | `10.0.0.201` | `6A:69:11:AA:00:A2` | `6A:69:11:AA:10:A2` | 60GB (NVMe Part) |
| **control-2** | `10.0.0.202` | `6A:69:11:AA:00:A3` | `6A:69:11:AA:10:A3` | 60GB (NVMe Part) |

### 3.2 Worker Nodes (Storage & General Purpose)
Worker nodes are optimized for storage (Ceph) and general workloads, each with 7 vCPUs and 36GB RAM.

| VM Name | IP Address | MAC (talos-nat) | MAC (lb-net) | Primary Storage | Extra Disks |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **worker-0** | `10.0.0.110` | `6A:69:11:AA:00:A4` | `6A:69:11:AA:10:A4` | 90GB NVMe | 2TB HDD, 20GB Ceph Meta |
| **worker-1** | `10.0.0.111` | `6A:69:11:AA:00:A5` | `6A:69:11:AA:10:A5` | 90GB NVMe | 2TB HDD, 20GB Ceph Meta |
| **worker-2** | `10.0.0.112` | `6A:69:11:AA:00:A6` | `6A:69:11:AA:10:A6` | 90GB NVMe | 2TB HDD, 20GB Ceph Meta |
| **worker-3** | `10.0.0.113` | `6A:69:11:AA:00:A7` | `6A:69:11:AA:10:A7` | 90GB NVMe | 2TB HDD, 20GB Ceph Meta |

### 3.3 Inference Nodes (GPU Workloads)
Inference nodes are pinned to specific CPU cores and optimized for GPU tasks, each with 8 vCPUs and 32GB RAM.

| VM Name | IP Address | MAC (talos-nat) | MAC (lb-net) | CPU Pinning | Storage |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **inference-0**| `10.0.0.120` | `6A:69:11:AA:00:A8` | `6A:69:11:AA:10:A8` | `0-13,28-41` | NVMe (Remainder) |
| **inference-1**| `10.0.0.121` | `6A:69:11:AA:00:A9` | `6A:69:11:AA:10:A9` | `14-27,42-55`| NVMe (Remainder) |

## 4. Storage Infrastructure

### 4.1 Physical NVMe Partitioning (Netac 250GB SSDs)
The cluster utilizes four Netac 250GB NVMe SSDs partitioned as follows:

1. **Drive ...362996**:
   - Part 1 (90GB): `worker-0` OS
   - Part 2 (90GB): `worker-1` OS
   - Part 3 (20GB): `worker-0` Ceph Metadata
   - Part 4 (20GB): `worker-1` Ceph Metadata

2. **Drive ...362935**:
   - Part 1 (90GB): `worker-2` OS
   - Part 2 (90GB): `worker-3` OS
   - Part 3 (20GB): `worker-2` Ceph Metadata
   - Part 4 (20GB): `worker-3` Ceph Metadata

3. **Drive ...362830**:
   - Part 1 (60GB): `control-1` OS
   - Part 2 (Remainder): `inference-0` OS

4. **Drive ...362984**:
   - Part 1 (60GB): `control-2` OS
   - Part 2 (Remainder): `inference-1` OS

### 4.2 Bulk Storage (SATA HDDs)
Four 2TB Seagate (ST2000DM008) drives are passed through to worker nodes:
- `ZFL32CQR` -> `worker-0`
- `ZFL32BZX` -> `worker-1`
- `ZFL32BA2` -> `worker-2`
- `ZFL34JEA` -> `worker-3`

## 5. Security & Isolation
- **VLAN 20**: Used on the `lb-net` (application) bridge to isolate external traffic.
- **NAT**: The `talos-nat` network is NATed through the host's `enp5s0` interface for internet access.
- **ARP Optimization**: Host-level sysctl tweaks (`arp_ignore=1`, `arp_announce=2`) and `rp_filter=0` are applied to handle multi-homed VM traffic correctly.
