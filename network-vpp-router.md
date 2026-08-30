# BlueField VPP router design

## Target shape

The CRS812 is the wiring and scheduling point; it is not the Internet router.
BlueField owns inter-VLAN routing, policy, NAT44, and IPv6 forwarding through
one tagged high-speed link.

```text
primary ISP port  -- primary-WAN VLAN --+
backup ISP port   -- backup-WAN VLAN  --+-- CRS812 -- tagged trunk -- BlueField VPP
LAN/fabric/IoT/guest/management VLANs --+                         |
                                                                  +-- NAT44 + ACLs
                                                                  +-- native IPv6
```

The WAN VLANs must contain only their physical ISP port and the BlueField
trunk. They must have no CRS812 SVI, no untagged LAN member, and no path to the
switch management CPU. The old `router` host is now a LAN service machine for
DNS, DHCP, netboot, WireGuard, and recovery access. It is not in the normal
packet-forwarding path; the separately named `router-rollback` closure can
temporarily restore legacy routing during an attended recovery.

The primary physical map is confirmed and live. CRS812 `sfp56-8` is the ISP
access port in VLAN 100, which reaches the BlueField as tagged traffic on
`qsfp56-1-1` over the existing 100G CR4/RS-FEC link. Do not use `sfp56-7`: its
5 m SFP28 DAC is linked at 25G to Rock-5B. The planned LAN replacement is
tagged VLAN 10; the accepted transition still carries the existing flat LAN
untagged while its ports are inventoried.

VLAN IDs, addresses, MTUs, service publications, and QoS classes belong in one
Nix topology value. VPP startup CLI and RouterOS membership should be rendered
from that value. The current proving ground follows this pattern in
`machines/aarch64/bluefield2/vpp-lab-topology.nix`; VLANs 3901--3903 and all
documentation prefixes are test-only.

## Data and control planes

- VPP owns the BlueField data port and one subinterface per security zone.
  Linux retains OOB management and RShim recovery.
- NAT44-ED is used only for IPv4. TCP MSS is derived from the WAN MTU, not
  copied as a second constant. Published TCP and UDP ports are generated from
  the service declaration.
- IPv6 is routed without NAT66. The primary ISP delegated prefix is split into
  one /64 per LAN zone. ICMPv6 control and Packet Too Big are explicitly
  permitted; unsolicited inbound traffic remains denied except for declared
  services.
- VPP itself acquires DHCPv4 and DHCPv6 IA_NA/PD on `bf0.100`, and learns the
  IPv6 default through router advertisements. Delegated `/64`s are assigned
  from VPP's prefix group to the LAN-zone interfaces; VPP refreshes their
  router advertisements when the delegated prefix changes. The WAN fast path
  therefore does not depend on a Linux LCP interface. Static lab prefixes must
  not survive the production switch.
- IPv6 uRPF stays disabled on the WAN interface. The provider's DHCPv6-PD
  reply originates from a link-local address, which VPP's loose uRPF rejects
  before the WAN ACL can admit UDP/546. The WAN ACL remains the ingress
  boundary and strict IPv6 uRPF remains enabled on inside interfaces.
- A future native-IPv6 second provider should advertise its own delegated
  prefix and use source-specific routing. When it fails, stop advertising its
  prefix and deprecate existing addresses. Do not hide this with NAT66. The
  current phone backup is deliberately control-only and installs no default.
- Each WAN receives an independent health check and route preference. Loss of
  gateway reachability withdraws that default and its NAT pool. qBittorrent's
  publication follows the active IPv4 address; failback is delayed to prevent
  route flapping.

## Firewall and QoS policy

The default inter-zone decision is deny. Trusted LAN may initiate Internet
traffic; restricted/bulk may initiate only declared services; WAN may enter
only published services and required IPv6 control traffic. NAT state handles
IPv4 return traffic and reflexive ACL state handles IPv6 return traffic.

VPP assigns DSCP at the trust boundary, so endpoint markings are never
trusted. The CRS812 performs scheduling on the actual ISP egress port. The
staged `nixos-wan` manager uses weighted service for ordinary/bulk/streaming/
interactive traffic and strict service for control traffic. At cutover:

1. Bind the manager only to the confirmed ISP-facing port.
2. Set aggregate egress just below the measured provider policer rate.
3. Cap strict queues so they cannot starve weighted traffic.
4. Keep PFC disabled on both WAN ports. RoCE PFC remains confined to TC3 on
   fabric ports.

The backup WAN needs its own egress rate and therefore its own manager or an
independent port-rate override.

DPDK is not a prerequisite for this policy.  VPP's old DPDK HQoS integration
was moved to `extras/deprecated` in 2020 with the upstream explanation that it
had not been functional for a long time.  VPP 26.06 contains a new, explicitly
development-status hardware Traffic Management framework, but neither its
DPDK plugin nor its RDMA plugin registers an implementation.  The production
split is therefore deliberate: VPP classifies and rewrites DSCP, while the
CRS812 ASIC owns queues, weighted/strict scheduling, and port-rate shaping.
Changing the BlueField dataplane driver does not change those capabilities.
Doing the shaping on the DPU itself would be a separate VPP driver-integration
project, not a startup option that should influence this cutover.

## Production cutover

1. Preserve a live export and finish the complete VLAN-1/LAN port inventory.
   The confirmed primary endpoints are CRS812 `sfp56-8` and BlueField
   `qsfp56-1-1`. Live FDB entries prove the inside path as CRS812
   `qsfp56-dd-1-1` to CRS804 `qsfp56-dd-1-1`, then CRS804 `qsfp56-dd-2-1` to
   CRS510 `qsfp28-1-1`.
2. Import the existing switch objects with a zero-change plan. Then pre-stage
   VLAN 100, VLAN 50, and the empty `sfp56-8` Ethernet settings while bridge
   VLAN filtering remains off. This was completed on 2026-08-28: 48 existing
   objects are in state, the pre-stage applied as two additions and three
   in-place changes, and its post-apply plan is empty.
3. Build and copy four closures before the outage: BlueField transition and
   lab rollback, plus old-router service-only and full-routing rollback. The
   BlueField closures are cross-compiled and addressed through its `.22` OOB
   Linux interface; both router closures are addressed through `.31`.
4. Wake the old iPhone and require k3's WiFi WAN to have a DHCP lease. Prove an
   allowed flow and a rejected qBittorrent/unapproved flow before touching
   gateway ownership.
5. Apply the two-property CRS cutover plan: enable bridge VLAN filtering and
   disable the switch's old `192.168.25.1` address. Activate the old router's
   service-only closure, then the BlueField transition closure. VPP now owns
   `.23.1`, `.25.1`, and `.50.1`; the old router retains DNS, DHCP, netboot,
   WireGuard, and application control on `.31`.
6. Before moving the ISP cable, verify LAN, WiFi, fabric, `.31` services, and
   an allowed control flow through the managed k3/iPhone fallback.
   Only then move the ISP cable to CRS812 `sfp56-8`.
7. Require DHCPv4 on `bf0.100`, DHCPv6-PD, the RA-learned IPv6 default, public
   IPv4/IPv6 reachability, qBittorrent publication, WireGuard, PMTUD, and NAT
   state before acceptance. Keep the old cable position and both rollback
   closures until the observation period passes.

The handoff through step 7 completed on 2026-08-28. The ISP cable is live in
CRS812 `sfp56-8`; VPP acquired `212.51.146.97/24`, its DHCP default, an
RA-learned IPv6 default, and delegated prefix `2a02:168:58b4::/48`. The legacy
flat LAN keeps delegated subnet zero (`2a02:168:58b4::/64`) so existing client
addresses remain valid, while WiFi uses subnet 50. DNS and DHCP remain on the
old router as service host `192.168.23.31`; clients must not continue querying
the new VPP gateway at `.1` for DNS.

Rollback is the exact reverse: move the cable back, activate `router-rollback`
through `.31`, activate `bluefield2-transition-cross` through `.22`, then
apply the RouterOS rollback renderer. Its only deletions are the two VLAN rows
created during pre-staging; it restores the empty ISP cage and turns filtering
off.

## K3 phone out-of-band recovery

The phone is not a second VPP WAN. K3 retains it as an out-of-band recovery
link with a deliberately narrow policy. Exact source hosts and destination
control ports come from
`network.policies.backupWan`; `arr-servers` (`192.168.23.15`) is absent, and a
final forwarding drop prevents rejected traffic from falling through to an
ordinary default route. The edge host also rejects new WiFi input, blocks IPv6
on the handset link, and applies the same port allowlist to its own output.

Rock's USB/iPhone path and VLAN-101 transit were independently proved first.
The removable phone then left with its owner, so k3's RTL8852BE was staged for
the old `iPhone (77)` hotspot instead. The old phone is now USB-attached to k3;
`ipheth` is preferred over WiFi, with both paths constrained by the same
control-only policy. The live CRS812 FDB resolves k3 behind `sfp56-6`, which
carries VLAN 101 to the BlueField trunk; the generated untagged bootstrap
address `192.168.23.30` remains available for recovery.

The lab injected only `1.1.1.1/32` and `9.9.9.9/32` for its acceptance tests.
The temporary gateway-handoff supervisor was retired on 2026-08-29 after the
primary WAN was accepted. The transition and final production plans now both
forbid a VPP default through k3. VPP may retain the VLAN-101 diagnostic address,
but it never uses that interface as an Internet next hop or NAT outside.

K3 keeps an `unreachable default` at metric 32767 in policy table 101. This is
the fail-closed route when the handset has no lease; the iPhone's DHCP default
uses metric 4096 and supersedes it only while the WiFi WAN is actually up.
Phone-bound local output goes through an idempotently rebuilt private firewall
chain, so repeated firewall reloads cannot accumulate stale policy copies.

The inactive-path test from Trex was completed on 2026-08-28: traffic sourced
from `198.18.10.2` crossed VPP and received an unreachable response from k3,
rather than falling through to the primary WAN. After the old iPhone was woken,
k3 associated at -38 dBm and received `172.20.10.13/28`; its DHCP default took
precedence over the fail-closed route. The complete Trex -> VPP -> k3 -> iPhone
path then passed 5/5 ICMP, HTTP 301, and HTTPS 200 tests. K3 recorded exactly
three new masqueraded flows. An unapproved source passed 0/3 ICMP and an
approved source's TCP/81 probe also failed; six packets reached the explicit
deny rule and the NAT counter did not increase. K3 was promoted to a
boot-persistent generation only after these positive and negative tests. The
matching BlueField generation was initially promoted through the hive's
dedicated `bluefield2-transition-cross` node. The ordinary
`bluefield2-cross` target now carries the accepted DPDK/host-PF production
closure; the transition target remains the RDMA/no-host-PF rollback. This
evidence is historical validation of k3's isolation policy, not an active VPP
failover feature.

## Acceptance evidence from the isolated lab

On 2026-08-28, VPP 26.06 on BlueField passed the 18-case IPv4/IPv6 NAT and ACL
matrix. At a 1500-byte simulated WAN MTU it forwarded 41.7 Gbit/s of IPv6 ACL
traffic and 40.6 Gbit/s of aggregate IPv4 NAT traffic across six NAT workers.
A deliberately single-affinity IPv4 test reached 17.3 Gbit/s on one Cortex-A72
worker; this is why aggregate capacity must be tested with independent address
pairs. Routed round-trip latency averaged 0.102 ms for IPv4 NAT and 0.081 ms
for IPv6. Restricted traffic arrived at WAN with CS1, and the generated MSS was
1460.

The real-WAN acceptance run on 2026-08-30 exposed what the aggregate test hid.
One Trex IPv4 address reached only 13.26 Gbit/s because NAT44-ED selects the
worker for every new session by source address; the same host reached 22.99
Gbit/s over native IPv6, and three temporary IPv4 source addresses reached
23.36 Gbit/s in aggregate. CNAT was then tested on the isolated 3901/3902 path:
one source address was spread evenly over all six workers but stopped at 16.43
Gbit/s, while routing with CNAT detached reached 48.83 Gbit/s on the identical
path. CNAT 26.06 takes the shared timestamp reader lock on the packet hot path,
so it is retained only as a diagnostic lab and is not a production NAT44
replacement. Production was returned to its exact pre-test generation.

The follow-up NAT44-ED experiment fixed the actual single-client bottleneck.
Established sessions still follow VPP's global endpoint-dependent flow table,
but a genuinely new dynamic session now chooses its worker from the complete
source/destination address and port tuple instead of the inside source address
alone. One ordinary Trex IPv4 address then reached 23.26 Gbit/s receiver
goodput with 16 parallel iPerf streams; only 1,138 NAT handoff-congestion drops
were recorded, versus millions before the change. A forced-IPv4 Ookla run
against the local 100G Zürich server measured 22.79 Gbit/s download and 23.29
Gbit/s upload with zero reported packet loss. The result is independently
published as `9d389719-7c93-4cea-996b-5424f36d1472`.

Connection scale survived the same change: VPP held 53,266 live translations,
including 29,056 TCP and 24,207 UDP sessions, while qBittorrent remained
reachable and its TCP/UDP 17026 publications remained installed. qBittorrent's
sessions appeared in every worker pool. The remaining performance defect is
queueing rather than NAT capacity: the IPv4 Ookla run reported 0.715 ms
download loaded-latency IQM, but 11.699 ms upload IQM and a 414.797 ms worst
upload sample. The CRS812 WAN shaper should be tuned below the provider policer
before calling loaded latency complete.

This patch is isolated behind `bluefield2.vpp.nat44FlowWorkers.enable` and the
`bluefield2-nat44-flow-workers-cross` review target. It is live through a
non-persistent `test` activation while the booted generation remains the exact
pre-test rollback. The same closure also makes IPv6 publication reconciliation
wait for VPP's CLI and retry if DHCPv6-PD has not arrived yet; the existing
30-second timer then keeps the prefix-aware ACLs current.

The primary CRS812 endpoint is the live `sfp56-8` ISP cage; `sfp56-7` remains
Rock-5B's live 25G link. The legacy-flat handoff is active: VLAN 100 contains
only `sfp56-8` and BlueField, VLAN 50 follows the FDB-proved core path, all
existing untagged ports remain in VLAN 1, and bridge VLAN filtering is on.
Post-cable checks proved real ISP DHCPv4, DHCPv6-PD/RA, public IPv4 and IPv6
from Trex and `arr-servers`, and qBittorrent's TCP/UDP publication. The measured
LAN-to-gateway RTT averaged 0.098 ms. IPv6 public service rules stay disabled
until stable host IIDs and prefix-aware ACL updates are defined; the WAN queue
manager remains unbound until the provider policer is measured.

## BlueField performance tuning protocol

Treat tuning as an A/B experiment, not as a bag of boot flags.  Preserve the
same VLAN, ACL, NAT, MTU, worker, queue, buffer, and traffic mix while comparing
the RDMA and DPDK mlx5 drivers.  For every saturated run, clear and then record
`show runtime`, `show errors`, `show hardware-interfaces bf0`, `show buffers`,
Linux NIC counters, aggregate goodput, retransmits, and latency under load.
`Vectors/Call` is particularly important: FD.io has an open CX6/CX7 report in
which the DPDK mlx5 input node leaves packets in a full receive queue and stays
around 200 vectors per call instead of filling a 256-packet VPP frame.

Change one variable at a time in this order:

1. Driver only: six workers and six RX/TX queues, 2 MiB hugepages, 10 KiB VPP
   buffers, unchanged policy and MTUs.  DPDK uses IOVA=VA and a minimal mlx5
   build; NVIDIA documents VA as the remedy for BlueField PA allocation
   failures and recommends building only mlx5 plus its required bus/mempool
   drivers.  The extra vmbus driver is compile-only compatibility for VPP's
   unconditional Linux header include.
2. Queue features: test mlx5 MPRQ (`mprq_en=1,rxqs_min_mprq=1`) and RX cache-line
   padding (`rxq_pkt_pad_en=1`) separately.  DPDK documents MPRQ as a
   small-packet optimization and padding as architecture-dependent; neither is
   a universal win.  Keep jumbo support, so do not use VPP's `no-multi-seg`.
3. Workers and RSS: repeat 2/4/6/7-worker sweeps with at least one independent
   address pair per RX queue.  A single five-tuple measures one RSS queue and
   one worker, not router capacity.  Queue count should normally match worker
   count; inspect placement rather than assuming it.
4. Host isolation: only after the driver baseline, boot with CPU 0 as the sole
   housekeeping core and CPUs 1--7 isolated (`isolcpus=domain,managed_irq,1-7`,
   `nohz_full=1-7`, `rcu_nocbs=1-7`).  Keep NIC IRQs and Linux services on CPU 0.
   This needs a reboot and a before/after latency distribution, not merely a
   throughput sample.  Do not add x86-only CSIT flags to this Arm machine.
5. Rings and buffers: vary RX/TX descriptors only if counters show queue
   exhaustion or bursts show loss.  More descriptors can increase cache/TLB
   pressure.  The existing 1024 x 2 MiB hugepages are already present and the
   mailing-list consensus is that 1 GiB pages mainly improve large-allocation
   startup time; their forwarding-performance gain over 2 MiB pages is small.
6. Scale: verify at least 50,000 established NAT44 connections while running
   mixed packet sizes and latency probes.  One public IPv4 address has roughly
   one source-port space, regardless of a larger VPP session table; add public
   addresses before interpreting approximately 64K port exhaustion as a CPU or
   hugepage limit.  IPv6 routing has no corresponding NAT port ceiling.

The first tuning target is robust 25 Gbit/s Internet service with policy and
headroom, not a pretty one-way maximum. The six-worker RDMA baseline reached
45.10 Gbit/s across six simultaneous TCP flows with zero retransmits, and idle
routed RTT averaged about 0.07 ms after neighbour warm-up. DPDK is now the
production choice because the native host-PF representor requires the mlx5
DPDK path; RDMA remains the explicit rollback. The retained DPDK profile must
continue to preserve jumbo, NAT, ACL, IPv6, and loaded-latency correctness.

### RDMA versus DPDK measurements

The first BlueField DPDK A/B on 2026-08-28 produced the following results.
All DPDK rows use IOVA=VA, six workers/queues, the minimal mlx5 build, a 3 GiB
VPP main heap, 2 MiB hugepages, and the full NAT/ACL/QoS/IPv6 topology.

| Dataplane and workload | Goodput | Retransmits | Relevant observation |
| --- | ---: | ---: | --- |
| RDMA, six TCP flows | 45.10 Gbit/s | 0 | Existing reliable baseline |
| DPDK, 1024 RX descriptors, fixed collision-heavy tuples | 31.60 Gbit/s | 350,008 | 350,942 mlx5 RX misses |
| DPDK, 4096 descriptors, same fixed tuples | 27.42 Gbit/s | 0 | Larger ring removes the loss |
| DPDK, 4096 descriptors plus RX padding, same tuples | 28.50 Gbit/s | 0 | About 4% better; jumbo still works |
| DPDK, padded 4096 ring, 48 balanced streams | 33.21 Gbit/s | 0 | All six queues busy, no RX misses |
| RDMA, 48 balanced streams | 35.89 Gbit/s | 1,231,476 | Higher goodput but poor overload behaviour |
| RDMA, controlled 24 Gbit/s | 24.00 Gbit/s | 0 | 0.154/0.155 ms IPv4/IPv6 loaded RTT, no loss |
| DPDK, controlled 24 Gbit/s | 23.72 Gbit/s | 0 | 0.074/0.116 ms loaded RTT; 2/500 IPv6 probes lost |

DPDK also sustained 59,999 established NAT44 sessions (60,000 requested),
with no RX miss or congestion counter and more than 35,000 free VPP buffers.
That proves connection scale is not the throughput limiter.  A single public
IPv4 address remains the limiting resource at roughly one TCP/UDP source-port
space.

Two plausible mlx5 optimizations were rejected on correctness or overload
evidence.  MPRQ selected its NEON vector path, but both explicit 2 KiB and 8 KiB
strides dropped every tested packet larger than 1500 bytes through this VPP
integration.  Ordinary 2 KiB/scatter buffers preserved jumbo and reached the
24 Gbit/s target, but selected scalar RX and recorded 1.96 million mlx5
out-of-buffer events plus 3.35 million retransmits in the balanced ceiling
test.  The retained DPDK profile therefore uses 10 KiB buffers, 4096 RX
descriptors, and `rxq_pkt_pad_en=1`; it is the lossless DPDK production
profile. The faster RDMA profile remains useful as a no-host-PF rollback.

The host-PF path was accepted on 2026-08-29 after restoring the card's factory
`EMBEDDED_CPU` mode. VPP discovered the external host PF as a native mlx5 DPDK
representor, and the old router reached Trex at 6.9 Gbit/s in either direction
with roughly 0.18 ms routed latency. That throughput is the negotiated PCIe
Gen3 x1 adapter ceiling (7.876 Gbit/s available), not a VPP or BlueField link
ceiling; the internal representor and physical uplink both report 100 Gbit/s.

Primary references:

- [FD.io CSIT test environment](https://docs.fd.io/csit/master/report/vpp_performance_tests/test_environment.html)
  for isolation, tickless workers, RCU offload, NUMA policy, hugepages, queue
  counts, and controlled startup settings.
- [VPP system tuning guide](https://wiki.fd.io/view/VPP/How_To_Optimize_Performance_(System_Tuning))
  for the upstream tuning checklist (noting that its validation is primarily
  on Intel systems).
- [DPDK mlx5 driver guide](https://doc.dpdk.org/guides-26.03/nics/mlx5.html)
  for bifurcated ownership, CQE compression, MPRQ, RX padding, eMPW, and
  BlueField-specific defaults.
- [NVIDIA BlueField DPDK troubleshooting guide](https://networking-docs.nvidia.com/bfswtroubleshooting/mlnx_dpdk)
  for the supported minimal driver build and IOVA=VA guidance.
- [FD.io mlx5 DPDK burst discussion](https://www.mail-archive.com/vpp-dev%40lists.fd.io/msg19021.html)
  and [open CX6/CX7 short-read issue](https://github.com/FDio/vpp/issues/3551)
  for why `Vectors/Call` must be measured.
- [FD.io RDMA/LCP performance thread](https://www.mail-archive.com/vpp-dev%40lists.fd.io/msg18947.html)
  for the recommended reduction from realistic topology to the simple CSIT
  case, then adding VLAN/LCP/features back one at a time.
- [FD.io hugepage allocation discussion](https://lists.fd.io/g/vpp-dev/topic/rfc_change_of_hugepage/10641099)
  for the practical 2 MiB versus 1 GiB trade-off.
- [FD.io's DPDK HQoS deprecation](https://github.com/FDio/vpp/commit/548d70de68a4bfe85e1ef2f00e0d11448ea63ed6)
  and [VPP 26.06 Traffic Management framework](https://github.com/FDio/vpp/blob/v26.06/src/vnet/tm/FEATURE.yaml)
  for why the tested DPDK profile is not treated as a working shaper.
