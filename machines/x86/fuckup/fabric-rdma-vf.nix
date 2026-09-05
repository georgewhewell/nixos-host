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
  # the mlx5 VF has its own in-kernel RDMA CM endpoint.
  systemd.services.fuckup-rdma-vf = {
    description = "Create fuckup's host RoCE SR-IOV VF";
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

      sriov=/sys/class/net/$pf/device/sriov_numvfs
      current=$(<"$sriov")
      if [[ "$current" == 0 ]]; then
        echo 1 >"$sriov"
      elif [[ "$current" != 1 ]]; then
        echo "$pf already has $current VFs; refusing to change it" >&2
        exit 1
      fi

      # Locate the VF through the PF's own virtfn0 link, whatever udev called
      # it — VF names are PCI-derived and exactly as fragile as PF names.
      vfdev=
      for _ in {1..50}; do
        vfdev=$(ls "/sys/class/net/$pf/device/virtfn0/net" 2>/dev/null | head -n1 || true)
        [[ -n "$vfdev" ]] && break
        sleep 0.1
      done
      [[ -n "$vfdev" ]] || {
        echo "VF netdev did not appear under $pf/device/virtfn0" >&2
        exit 1
      }

      # Stable VF name for the 05-fuckup-rdma-vf networkd match; idempotent.
      if [[ "$vfdev" != "${vfName}" ]]; then
        ip link set "$vfdev" down
        ip link set "$vfdev" name ${vfName}
      fi

      ip link set "$pf" vf 0 \
        mac ${rdma.mac} \
        spoofchk off \
        trust on
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
}
