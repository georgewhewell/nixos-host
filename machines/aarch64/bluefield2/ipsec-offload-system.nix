{lib, network, pkgs, ...}: {
  imports = [./hostpf-system.nix];

  # Build-only Arm-side canary. The production BlueField target and its live
  # VPP process remain unchanged until this closure has been reviewed.
  services.bluefield2-ipsec-ikev2.kernelOffload.enable = true;

  environment.systemPackages = [pkgs.ethtool pkgs.iproute2 pkgs.strongswan];

  systemd.services.bluefield-uplink-ipsec-capability = {
    description = "Report BlueField Arm-uplink IPsec crypto-offload capability";
    wantedBy = ["multi-user.target"];
    after = ["sys-subsystem-net-devices-${network.ports.bluefield2.vppData.linuxName}.device"];
    bindsTo = ["sys-subsystem-net-devices-${network.ports.bluefield2.vppData.linuxName}.device"];
    path = [pkgs.coreutils pkgs.ethtool pkgs.gnugrep pkgs.kmod];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      dev=${lib.escapeShellArg network.ports.bluefield2.vppData.linuxName}
      modprobe esp4_offload
      modprobe esp6_offload

      ethtool -i "$dev"
      ethtool -k "$dev" | grep -E '^(esp-hw-offload|esp-tx-csum-hw-offload|tx-esp-segmentation):'
      if ! ethtool -k "$dev" | grep -q '^esp-hw-offload: on'; then
        echo "BlueField Arm uplink does not expose mlx5 IPsec crypto offload" >&2
        exit 1
      fi
    '';
  };
}
