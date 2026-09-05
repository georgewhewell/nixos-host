{
  lib,
  network,
  pkgs,
  ...
}: let
  baseKernel = pkgs.linuxKernel.packages.linux_7_2_rc2.kernel;
  ipsecKernel = baseKernel.override {
    structuredExtraConfig =
      (baseKernel.structuredExtraConfig or {})
      // (with lib.kernel; {
        XFRM_OFFLOAD = yes;
        INET_ESP_OFFLOAD = module;
        INET6_ESP_OFFLOAD = module;
        MLX5_EN_IPSEC = yes;
      });
  };
in {
  imports = [./hostpf-system.nix];

  # Build-only canary for the BlueField host PF. Loading this kernel is a
  # separate attended step; the ordinary router target remains the rollback.
  boot.kernelPackages = lib.mkOverride 40 (pkgs.linuxPackagesFor ipsecKernel);
  boot.kernelModules = ["esp4_offload" "esp6_offload"];

  environment.systemPackages = [pkgs.ethtool pkgs.iproute2 pkgs.strongswan];

  # This unit observes only. It does not add XFRM state, claim UDP ports, or
  # modify a route; a failed capability probe therefore cannot affect DNS or
  # the BlueField's live WAN dataplane.
  systemd.services.bluefield-hostpf-ipsec-capability = {
    description = "Report BlueField host-PF IPsec crypto-offload capability";
    wantedBy = ["multi-user.target"];
    after = ["sys-subsystem-net-devices-${network.routing.hostPf.router.linuxName}.device"];
    bindsTo = ["sys-subsystem-net-devices-${network.routing.hostPf.router.linuxName}.device"];
    path = [pkgs.coreutils pkgs.ethtool pkgs.gnugrep pkgs.kmod];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      dev=${lib.escapeShellArg network.routing.hostPf.router.linuxName}
      modprobe esp4_offload
      modprobe esp6_offload

      ethtool -i "$dev"
      ethtool -k "$dev" | grep -E '^(esp-hw-offload|esp-tx-csum-hw-offload|tx-esp-segmentation):'
      if ! ethtool -k "$dev" | grep -q '^esp-hw-offload: on'; then
        echo "BlueField host PF does not expose mlx5 IPsec crypto offload" >&2
        exit 1
      fi
    '';
  };
}
