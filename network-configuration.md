## define all of the configuration required to enable the following network setup:
### Consider the following host configuration
* there are 2 physical hosts:
- hegemon - (192.168.1.100)
this vm and other vms are running on hegemon

wjones@hegemon:~$ ip r
default via 192.168.1.1 dev eno1 proto static metric 100
172.16.0.0/16 dev virbr1 proto kernel scope link src 172.16.0.1
172.20.0.0/16 via 192.168.1.101 dev eno1 proto static metric 100
192.16.192.0/24 dev virbr2 proto kernel scope link src 192.16.192.1
192.168.0.0/16 dev eno1 proto kernel scope link src 192.168.1.100 metric 100
192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 linkdown

-

wjones@hegemon:~$ sudo iptables --list
Chain INPUT (policy ACCEPT)
target     prot opt source               destination

Chain FORWARD (policy ACCEPT)
target     prot opt source               destination

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination


wjones@hegemon:~$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
inet 127.0.0.1/8 scope host lo
valid_lft forever preferred_lft forever
inet6 ::1/128 scope host noprefixroute
valid_lft forever preferred_lft forever
2: eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
link/ether 50:65:f3:4b:41:ad brd ff:ff:ff:ff:ff:ff
altname enp0s25
altname enx5065f34b41ad
inet 192.168.1.100/16 brd 192.168.255.255 scope global noprefixroute eno1
valid_lft forever preferred_lft forever
inet6 fe80::4d92:8274:8251:b9a9/64 scope link noprefixroute
valid_lft forever preferred_lft forever
3: virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc htb state DOWN group default qlen 1000
link/ether 52:54:00:b1:a3:9b brd ff:ff:ff:ff:ff:ff
inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0
valid_lft forever preferred_lft forever
4: virbr2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
link/ether 52:54:00:75:49:82 brd ff:ff:ff:ff:ff:ff
inet 192.16.192.1/24 brd 192.16.192.255 scope global virbr2
valid_lft forever preferred_lft forever
5: virbr1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc htb state UP group default qlen 1000
link/ether 52:54:00:48:87:27 brd ff:ff:ff:ff:ff:ff
inet 172.16.0.1/16 brd 172.16.255.255 scope global virbr1
valid_lft forever preferred_lft forever
6: vnet0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master virbr1 state UNKNOWN group default qlen 1000
link/ether fe:54:00:a7:fe:cd brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc54:ff:fea7:fecd/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
7: vnet1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master virbr2 state UNKNOWN group default qlen 1000
link/ether fe:54:00:90:e8:47 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc54:ff:fe90:e847/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever


---
- hierophant - (192.168.1.101)
  wjones@hierophant:~$ ip r
  default via 192.168.1.1 dev enp5s0 proto static metric 106
  10.0.0.0/24 dev talos-bridge proto kernel scope link src 10.0.0.1
  172.16.0.0/16 via 192.168.1.100 dev enp5s0
  172.20.0.0/16 dev br-app proto kernel scope link src 172.20.0.1 metric 425
  192.168.1.0/24 dev enp5s0 proto kernel scope link src 192.168.1.101 metric 106

    sudo iptables --list
    Chain INPUT (policy ACCEPT)
    target     prot opt source               destination
    
    Chain FORWARD (policy ACCEPT)
    target     prot opt source               destination         
    ACCEPT     all  --  anywhere             172.20.0.0/16       
    ACCEPT     all  --  172.20.0.0/16        anywhere            
    ACCEPT     all  --  anywhere             10.0.0.0/24         
    ACCEPT     all  --  10.0.0.0/24          anywhere            
    ACCEPT     all  --  anywhere             anywhere            
    ACCEPT     all  --  anywhere             anywhere             state RELATED,ESTABLISHED
    ACCEPT     all  --  192.168.0.0/16       anywhere            
    ACCEPT     all  --  anywhere             anywhere            
    ACCEPT     all  --  anywhere             anywhere             state RELATED,ESTABLISHED
    
    Chain OUTPUT (policy ACCEPT)
    target     prot opt source               destination

[wjones@hierophant ~]$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
inet 127.0.0.1/8 scope host lo
valid_lft forever preferred_lft forever
inet6 ::1/128 scope host noprefixroute
valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
link/ether a0:8c:fd:d8:27:ba brd ff:ff:ff:ff:ff:ff
altname enxa08cfdd827ba
inet 192.168.1.101/24 brd 192.168.1.255 scope global noprefixroute enp5s0
valid_lft forever preferred_lft forever
inet6 fe80::f3e7:39b:f318:bd91/64 scope link noprefixroute
valid_lft forever preferred_lft forever
3: eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
link/ether a0:8c:fd:d8:27:b9 brd ff:ff:ff:ff:ff:ff
altname enp0s25
altname enxa08cfdd827b9
31: eno1.20@eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
link/ether a0:8c:fd:d8:27:b9 brd ff:ff:ff:ff:ff:ff
32: br-app: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
link/ether fe:69:11:aa:10:a1 brd ff:ff:ff:ff:ff:ff
inet 172.20.0.1/16 brd 172.20.255.255 scope global noprefixroute br-app
valid_lft forever preferred_lft forever
33: talos-bridge: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc htb state UP group default qlen 1000
link/ether 52:54:00:29:e8:70 brd ff:ff:ff:ff:ff:ff
inet 10.0.0.1/24 brd 10.0.0.255 scope global talos-bridge
valid_lft forever preferred_lft forever
34: vnet6: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a1 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a1/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
35: vnet7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a1 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a1/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
36: vnet8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a2 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a2/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
37: vnet9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a2 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a2/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
38: vnet10: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a3 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a3/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
39: vnet11: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a3 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a3/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
61: vnet12: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a4 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a4/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
62: vnet13: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a4 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a4/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
63: vnet14: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a5 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a5/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
64: vnet15: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a5 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a5/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
65: vnet16: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a6 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a6/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
66: vnet17: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a6 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a6/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
67: vnet18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a7 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a7/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
68: vnet19: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a7 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a7/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
88: vnet24: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a8 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a8/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
89: vnet25: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a8 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a8/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
90: vnet26: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master talos-bridge state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:00:a9 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:a9/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever
91: vnet27: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master br-app state UNKNOWN group default qlen 1000
link/ether fe:69:11:aa:10:a9 brd ff:ff:ff:ff:ff:ff
inet6 fe80::fc69:11ff:feaa:10a9/64 scope link proto kernel_ll
valid_lft forever preferred_lft forever


- on hierophant are numerous virtual machines forming a kubernetes cluster
- all of these vms are on the 'talos-nat' (the k8s control subnet at 10.0.0.0/24)
- all of these vms have an interface defined with an address from 172.20.x.x/16
- there is a purelb load balancer in the cluster assigning connections from the 172.20.x.x/16 pool using the lb-net virtual network 

---

------------

THERE IS A ROUTE ON THE LOCAL NETWORK LIKE
172.20.0.0/16 -> 192.168.1.101

1) a physical network setup based on 192.168.x.x/16 with a default gateway of 192.168.1.1
2) we need to define network configuration so that
    1) any host attached to the 192.168.1.x/16 network can get to the load balancer addresses (172.20.0.0/16)
    2) any host attached to the 192.168.1.x/16 network can get to hierophant (192.168.1.101)
    3) any vm on any host on the 192.168.1.x/16 network can get to the internet
    4) any vm on any host on the 192.168.1.x/16 network can get to the load balancer addresses (172.20.0.0/16)
    5) any vm on any host on the 192.168.1.x/16 network can get to the kubernetes cluster host (192.168.1.101)

### Restoring Connectivity to Cluster Nodes

If the cluster nodes (VMs) do not recognize the network devices after a reconfiguration (e.g., "Destination Host Unreachable" or 0 packet counts in iptables), you should run the following diagnostics and restoration steps.

**On Hierophant:**

1. **Run Diagnostics:**
   This script will show the current state of bridges, VM interfaces, and ARP tables.
   ```bash
   /mnt/hegemon-share/code/kubernetes-setup/new-setup/04-diag-network.sh
   ```

2. **Cycle VM Interfaces (Lightweight):**
   If bridges are up but VMs aren't responding, try cycling the tap interfaces.
   ```bash
   /mnt/hegemon-share/code/kubernetes-setup/new-setup/03-cycle-network.sh
   ```

3. **Restart VMs (Full Restoration - Safe Sequence):**
   If the VMs still do not recognize their attached devices, a full restart of the VMs is required. 
   **Note:** The `06-drain-and-restore-vms.sh` script provides the safest method for clusters running ROOK/Ceph. It drains each node using `kubectl` before restarting the VM, and uncordons it only after it is healthy. **This script will abort if a node fails to drain to protect the cluster state.**
   ```bash
   /mnt/hegemon-share/code/kubernetes-setup/new-setup/06-drain-and-restore-vms.sh
   ```

4. **Restart VMs (Lightweight Sequence):**
   Use this if `kubectl` is not available or for a faster sequential restart.
   ```bash
   /mnt/hegemon-share/code/kubernetes-setup/new-setup/05-restore-vms.sh
   ```

The `172.20.0.0/16` network is managed by `hierophant` (192.168.1.101) via the `br-app` bridge.
To enable connectivity from `hegemon` and other hosts/VMs on the `192.168.1.x` network, the following route must be added:

**On Hegemon:**
```bash
sudo ip route add 172.20.0.0/16 via 192.168.1.101 dev eno1
```

**On VMs inside Hegemon (e.g., vscode-fedora):**
If the VM is using `hegemon` as its gateway, no change is needed once the route is added to `hegemon`.
If the VM is on a separate network (like `172.16.0.0/16`) and `hegemon` is its gateway (`172.16.0.1`), it should work automatically.

**Alternative (Physical Gateway):**
Add a static route on the physical gateway (`192.168.1.1`):
- Network: `172.20.0.0/16`
- Next Hop: `192.168.1.101`

**Update (2026-01-28):** Even with the gateway route, connectivity may fail due to asymmetric routing or host-level security.

### Troubleshooting Continued Connectivity Issues

If the route exists on the gateway but you still cannot ping `172.20.1.x` from `hegemon`:

1.  **Asymmetric Routing (RP Filter):**
    When `hegemon` pings `172.20.1.x`, it sends the packet to the gateway (`192.168.1.1`). The gateway forwards it to `hierophant` (`192.168.1.101`). `hierophant` responds. If `hierophant` sends the response directly back to `hegemon` (since they are on the same subnet), `hegemon` might drop it if strict reverse path filtering is enabled, because the response came from a different MAC address than the gateway it sent the request to (though usually RP filter is about the interface).
    
    More likely, `hierophant` might be dropping the packet if it expects traffic for `172.20.0.0/16` to only come from certain interfaces.

2.  **ICMP Redirects:**
    The gateway (`192.168.1.1`) should send an ICMP Redirect to `hegemon`, telling it to use `192.168.1.101` directly for `172.20.0.0/16`. Check if `hegemon` is ignoring these.
    ```bash
    sysctl net.ipv4.conf.eno1.accept_redirects
    ```

3.  **Hierophant Forwarding:**
    Ensure `hierophant` allows forwarding from `enp5s0` to `br-app` for the physical LAN subnet.
    In `02-setup-network.sh`, we previously had:
    ```bash
    sudo iptables -A FORWARD -i enp5s0 -o br-app -m state --state RELATED,ESTABLISHED -j ACCEPT
    ```
    This ONLY allowed return traffic. If `hegemon` pings `172.20.1.x` and it goes via the gateway, `hierophant` sees a NEW connection from `192.168.1.100` on `enp5s0` destined for `br-app`. **This was previously NOT explicitly allowed** unless there was another rule.

    **Fix (already updated in 02-setup-network.sh):**
    ```bash
    sudo iptables -A FORWARD -i enp5s0 -o br-app -s 192.168.0.0/16 -j ACCEPT
    ```

### Resolution: Maintaining VLAN 20 Isolation and Internal Routing

The `br-app` bridge on `hierophant` uses **VLAN 20** to isolate 'external' (load balancer) traffic and resolve issues with 'dual-home' adapters on the cluster VMs.

#### Configuration Strategy:
1.  **VLAN 20 Tagging**: The `br-app` bridge is enslaved to `eno1.20`. All traffic for `172.20.0.0/16` leaving `hierophant` via `eno1` is tagged with VLAN ID 20.
2.  **Internal Routing**: `hierophant` acts as a router between its management interface (`enp5s0` - 192.168.1.101) and the application bridge (`br-app` - 172.20.0.1).
3.  **Local Connectivity**: When `hegemon` (192.168.1.100) or other physical hosts want to reach `172.20.x.x`, they send traffic to `192.168.1.101` (untagged). `hierophant` receives this on `enp5s0`, routes it internally to `br-app`, and sends it to the VM.
4.  **Return Path**: Return traffic from the VM on `br-app` is routed by `hierophant` back through `enp5s0` to `hegemon` (untagged), provided the `rp_filter` is set to loose mode (2) to allow this asymmetric path.

#### Why this works:
This setup respects the requirement to isolate traffic on VLAN 20 for the physical wire (via `eno1`), but allows internal routing for hosts on the same physical management subnet (`enp5s0`) without requiring those hosts to be VLAN-aware.

**On Hierophant (after running updated 02-setup-network.sh):**
The `br-app` should be enslaved to `eno1.20`.
```bash
bridge link show br-app # Should show eno1.20 and vnetX interfaces
```

### Resolution: Enabling ICMP Redirects or Adding Persistent Routes

Since `net.ipv4.conf.eno1.accept_redirects = 0` on `hegemon`, it is ignoring the gateway's instructions to talk to `hierophant` directly.

#### Option A: Enable ICMP Redirects on Hegemon
This allows `hegemon` to learn the "shortcut" from the gateway.
```bash
sudo sysctl -w net.ipv4.conf.eno1.accept_redirects=1
sudo sysctl -w net.ipv4.conf.all.accept_redirects=1
```
To make this persistent, add to `/etc/sysctl.d/99-networking.conf`:
```text
net.ipv4.conf.eno1.accept_redirects=1
net.ipv4.conf.all.accept_redirects=1
```

#### Option B: Add a Persistent Static Route on Hegemon (Recommended)
This is the most reliable method as it avoids dependence on the gateway's redirect behavior and works even if redirects are disabled for security.

**Using NetworkManager (nmcli):**
```bash
sudo nmcli connection modify eno1 +ipv4.routes "172.20.0.0/16 192.168.1.101"
sudo nmcli connection up eno1
```
*Note: replace `eno1` with the actual connection name if it differs.*

**Using `ip route` (Temporary/Immediate):**
```bash
sudo ip route add 172.20.0.0/16 via 192.168.1.101 dev eno1
```

### Investigating Traceroute Timeout at Hierophant

If `traceroute` from `hegemon` reaches `hierophant` (192.168.1.101) but fails to go further:

```text
 1  hierophant.hierocracy.home (192.168.1.101)  0.146 ms
 2  * * *
```

This means `hierophant` is receiving the packet but not successfully forwarding it to the final destination (e.g., `172.20.1.20`) or the destination is not responding.

#### 1. Check Connectivity from Hierophant
On **hierophant**, verify if the host itself can reach the target:
```bash
ping -c 3 172.20.1.20
```
If this fails, the issue is between `hierophant` and the K8s cluster/PureLB.

#### 2. Check ARP on Hierophant
PureLB typically works by having cluster nodes respond to ARP requests for the LoadBalancer IP on the `br-app` bridge.
```bash
ip neigh show dev br-app | grep 172.20.1.20
```
If you see `<incomplete>`, then no node in the cluster is responding to ARP for that IP.

#### 3. Check Bridge Status
Ensure `br-app` has active ports (the VMs):
```bash
bridge link show br-app
```
You should see multiple `vnetX` interfaces connected to `br-app`.

#### 4. Check Iptables Stats
Verify if the FORWARD rules are being hit:
```bash
sudo iptables -nvL FORWARD | grep br-app
```
Look at the packet counts. If they are 0, traffic from `enp5s0` is not being matched by these rules. This usually indicates the packets are being dropped by the kernel **before** they reach the FORWARD chain.

#### 5. Reverse Path (RP) Filter
If `hegemon` sends a packet to `hierophant`'s `enp5s0`, but `hierophant` has a more specific route for the return path (or just a different interface `br-app` for that subnet), the kernel might drop the packet as "bogus" if `rp_filter` is set to strict mode (1).

Check the current settings:
```bash
sysctl -a | grep "\.rp_filter"
```
If these are `1`, it explains why `iptables` sees no packets. We need to set them to `2` (Loose) or `0` (Off).

**Fix (added to 02-setup-network.sh):**
```bash
for iface in all default enp5s0 br-app; do
    sudo sysctl -w net.ipv4.conf.${iface}.rp_filter=2
done
```

#### 6. Verify PureLB Configuration
PureLB must be configured to use the `br-app` interface (or whatever interface is connected to the `lb-net` virtual network in Libvirt). If PureLB is trying to send traffic out of a different interface, or if the Libvirt network `lb-net` is not correctly mapped to the host bridge `br-app`, connectivity will fail.

In `network-configuration.md`, `lb-net` is defined as:
```xml
<network connections='9'>
    <name>lb-net</name>
    <bridge name='br-app'/>
</network>
```
Ensure this matches the actual state on `hierophant` (`virsh net-dumpxml lb-net`).

--------



