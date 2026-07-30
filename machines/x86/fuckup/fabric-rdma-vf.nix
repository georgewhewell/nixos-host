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
      # br0.lan and its PF are intentionally MTU 1500.  Advertising a 4096-byte
      # RoCE path MTU on this child while the physical bridge path remains 1500
      # makes the target's first Identify response hit retry-exceeded.  Keep
      # this VF at 1500 (RoCE MTU 1024) unless the whole LAN bridge is migrated
      # to jumbo frames.
      MTUBytes = "1500";
      ActivationPolicy = "up";
      RequiredForOnline = "no";
    };
    networkConfig = {
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };
}
