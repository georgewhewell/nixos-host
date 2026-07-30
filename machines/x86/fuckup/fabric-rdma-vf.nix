{
  pkgs,
  network,
  ...
}: let
  pfName = "enp8s0f0np0";
  vfName = "enp8s0f0v0";
  rdma = network.hosts."fuckup-rdma";
in {
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
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      sriov=/sys/class/net/${pfName}/device/sriov_numvfs
      current=$(<"$sriov")
      if [[ "$current" == 0 ]]; then
        echo 1 >"$sriov"
      elif [[ "$current" != 1 ]]; then
        echo "${pfName} already has $current VFs; refusing to change it" >&2
        exit 1
      fi

      for _ in {1..50}; do
        [[ -e /sys/class/net/${vfName} ]] && break
        sleep 0.1
      done
      [[ -e /sys/class/net/${vfName} ]] || {
        echo "${vfName} did not appear" >&2
        exit 1
      }

      ip link set ${pfName} vf 0 \
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
      # br0.lan is unaffected: a Linux bridge adopts the *minimum* MTU of its
      # ports, and the igc/aquantia members remain at 1500.
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
