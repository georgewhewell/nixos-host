{
  pkgs,
  network,
  ...
}: let
  # The live ConnectX-4 Lx port, pinned by permanent MAC — it is the same
  # port that carries br0.lan and is inventoried as fuckup's primary MAC.
  # Never match PCI-path names ("enp8s0f1np1"): the DAC has already moved
  # ports once (2026-08-06), and on 2026-08-26 the udev rename raced and
  # lost, leaving the port as "eth1" and this unit failing on a nonexistent
  # sysfs path.
  pfMac = network.hosts.fuckup.mac;
  pfName = "cx4fabric0";
  vfName = "cx4rdma0";
  rdma = network.hosts."fuckup-rdma";
  # VF 1 belongs to the Windows build VM (windows-vm.nix), attached as a
  # macvtap. The PF tags it into the guest's VLAN in hardware, so the guest
  # never shares br0.lan with the workstation. Untagged (LAN) until the
  # builders VLAN exists on the gateway.
  winVfName = "cx4win0";
  win = network.hosts.windows;
  winVlan =
    if win.addresses ? builders
    then network.vlans.builders.id
    else null;
in {
  # Deterministic PF name, applied by udev at device-add from silicon
  # identity. Mirrors the strix 10-cx5-fabric rule.
  #
  # The 10G cap lives here too, NOT in a separate rule: udev applies only the
  # FIRST .link file that matches a device, so a second profile for this port
  # would silently shadow whichever sorts later. (It previously lived in
  # default.nix as "05-connectx-port-2-thermal-fallback", matched by PCI
  # path.) The cap itself: at 95-96C this ConnectX-4 Lx port stopped
  # training at 25G while the same Mellanox DAC remained solid at 10G. Keep
  # the host end matched to CRS510 sfp28-8 until airflow is fixed and 25G is
  # retested cool.
  systemd.network.links."10-cx4-fabric" = {
    matchConfig.PermanentMACAddress = pfMac;
    linkConfig = {
      Name = pfName;
      AutoNegotiation = false;
      BitsPerSecond = "10G";
      Duplex = "full";
      RxFlowControl = true;
      TxFlowControl = true;
    };
  };

  # Keep the workstation's live 25G PF in br0.lan and create one host VF for
  # RoCE.  A VF is necessary because a Linux bridge has no verbs device, while
  # the mlx5 VF has its own in-kernel RDMA CM endpoint. VF 1 is the Windows
  # VM's NIC.
  systemd.services.fuckup-rdma-vf = {
    description = "Create fuckup's RoCE and Windows VM SR-IOV VFs";
    wantedBy = ["network-pre.target"];
    before = [
      "network-pre.target"
      "systemd-networkd.service"
    ];
    path = [
      pkgs.coreutils
      pkgs.iproute2
      pkgs.ethtool
      pkgs.gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      # Resolve the PF by permanent MAC rather than by name: the 10-cx4-fabric
      # rename only applies at device add, so on a live `switch` the port may
      # still carry an old name. Skip VFs (they have a physfn link) — a VF
      # whose administrative MAC was already set could otherwise shadow the PF.
      pf=
      for dev in /sys/class/net/*; do
        name=''${dev##*/}
        drv=$(readlink -f "$dev/device/driver" 2>/dev/null || continue)
        [[ "''${drv##*/}" == mlx5_core ]] || continue
        [[ -e "$dev/device/physfn" ]] && continue
        [[ "$(ethtool -P "$name" | awk '{print $3}')" == "${pfMac}" ]] || continue
        pf=$name
        break
      done
      [[ -n "$pf" ]] || {
        echo "no mlx5 PF with permanent MAC ${pfMac}" >&2
        exit 1
      }

      # mlx5 can only change the VF count through zero, which destroys every
      # VF (and with VF 0 the NVMe/RDMA models controller). Only ever do that
      # when the count is actually wrong; a steady-state restart is a no-op.
      sriov=/sys/class/net/$pf/device/sriov_numvfs
      current=$(<"$sriov")
      if [[ "$current" != 2 ]]; then
        [[ "$current" == 0 ]] || echo 0 >"$sriov"
        echo 2 >"$sriov"
      fi

      # Locate each VF through the PF's own virtfnN link, whatever udev called
      # it — VF names are PCI-derived and exactly as fragile as PF names.
      # Stable names for the networkd matches below; idempotent.
      name_vf() {
        local idx=$1 want=$2 vfdev=
        for _ in {1..50}; do
          vfdev=$(ls "/sys/class/net/$pf/device/virtfn$idx/net" 2>/dev/null | head -n1 || true)
          [[ -n "$vfdev" ]] && break
          sleep 0.1
        done
        [[ -n "$vfdev" ]] || {
          echo "VF netdev did not appear under $pf/device/virtfn$idx" >&2
          exit 1
        }
        if [[ "$vfdev" != "$want" ]]; then
          ip link set "$vfdev" down
          ip link set "$vfdev" name "$want"
        fi
      }
      name_vf 0 ${vfName}
      name_vf 1 ${winVfName}

      ip link set "$pf" vf 0 \
        mac ${rdma.mac} \
        spoofchk off \
        trust on

      # The guest is untrusted: spoof checking on, no promiscuous/trust.
      ip link set "$pf" vf 1 \
        mac ${win.mac} \
        vlan ${if winVlan == null then "0" else toString winVlan} \
        spoofchk on \
        trust off
    '';
  };

  # This exact match must sort before default.nix's broad 10-mlx5 rule.
  # Otherwise networkd enslaves the VF into br0.lan: tcpdump then sees ARP
  # replies on the slave, but the kernel correctly refuses to give that slave
  # an independent L3 neighbour table.
  systemd.network.networks."05-fuckup-rdma-vf" = {
    matchConfig.Name = vfName;
    address = [(network.cidrOf "fabric" rdma.addresses.fabric)];
    linkConfig = {
      MACAddress = rdma.mac;
      # Jumbo, giving a 4096-byte RoCE path MTU (the steps are
      # 256/512/1024/2048/4096, so 9000 buys the largest one).
      #
      # An earlier revision pinned this to 1500 believing br0.lan's 1500 was
      # the binding constraint. It is not: this VF is deliberately *not* a
      # bridge port, so its frames go VF -> PF -> wire and never traverse
      # br0.lan. The real blocker was trex's switchdev representor mlxlan0r1
      # sitting at 1500 and dropping everything larger. With that raised (see
      # machines/x86/trex/fabric-rdma-vf.nix) the whole path passes
      # ping -M do -s 8972, and 1 MiB NVMe-oF reads went from 3.7 MiB/s with
      # controller reconnects to 2279 MiB/s with zero out_of_sequence growth.
      #
      # br0.lan is independent of this: it is jumbo in its own right since
      # 2026-08-06, once every bridge member (including the carrier-less
      # Aquantia) was raised to 9000 -- a Linux bridge adopts the *minimum*
      # MTU of its ports.
      MTUBytes = "9000";
      ActivationPolicy = "up";
      RequiredForOnline = "no";
    };
    networkConfig = {
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };

  # In legacy SR-IOV mode the ConnectX eswitch forwards by MAC: the PF vport
  # receives only the PF's own MAC (plus its unicast list), and bridge
  # promiscuity does not reach into the eswitch. br0.lan has a networkd-
  # generated MAC, so frames from a VF to this host (the Windows VM replying
  # to fuckup, e.g. the Hydra jump) left through the uplink, which will not
  # hairpin them back. Put the bridge MAC on the PF's unicast list.
  systemd.services.fuckup-pf-bridge-mac = {
    description = "Deliver br0.lan's MAC to the ConnectX PF vport";
    wantedBy = ["multi-user.target"];
    bindsTo = ["sys-subsystem-net-devices-br0.lan.device"];
    after = [
      "sys-subsystem-net-devices-br0.lan.device"
      "fuckup-rdma-vf.service"
    ];
    partOf = ["fuckup-rdma-vf.service"];
    path = [pkgs.iproute2];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mac=$(</sys/class/net/br0.lan/address)
      bridge fdb replace "$mac" dev ${pfName} self local
    '';
  };

  # The Windows VM's VF carries no host addressing; it exists only as the
  # macvtap lower device. Sorts before 10-mlx5 for the same reason as above.
  systemd.network.networks."05-fuckup-win-vf" = {
    matchConfig.Name = winVfName;
    linkConfig = {
      ActivationPolicy = "up";
      RequiredForOnline = "no";
    };
    networkConfig = {
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };
}
