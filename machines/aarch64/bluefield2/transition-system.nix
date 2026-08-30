{
  config,
  lib,
  network,
  pkgs,
  ...
}: let
  plan = import ./vpp-transition-plan.nix {
    inherit lib network;
    driver = config.bluefield2.vpp.dataplaneDriver;
    hostPfMode = config.bluefield2.hostPf.mode;
    hostPfEnable = config.bluefield2.hostPf.mode == "vpp-representor";
  };
  transition = network.routing.production.transition;
  ipv6PublicationsEnabled =
    network.routing.production.firewall.publishIpv6Services
    && plan.ipv6Publications != [];
  ipv6PublicationSync = pkgs.callPackage ../../../packages/vpp-ipv6-publication-sync {};
in {
  imports = [./default.nix];

  # Explicit cutover closure.  vpp-lab.nix still supplies the tested package,
  # core pinning, hugepages, link setup and Linux ownership boundary; only the
  # startup graph and the two additional plugins differ.
  services.vpp = {
    startupConfig = lib.mkForce plan.startupConfig;
    settings.plugins.plugin = {
      "dhcp_plugin.so".enable = true;
      "urpf_plugin.so".enable = true;
    };
  };

  environment.etc."vpp/ACTIVE-PLAN".text = "legacy-flat-transition\n";
  environment.etc."vpp/ipv6-publications.json" = lib.mkIf ipv6PublicationsEnabled {
    text = builtins.toJSON plan.dynamicIpv6AclPolicy;
    mode = "0444";
  };

  systemd.services.vpp-ipv6-publication-sync = lib.mkIf ipv6PublicationsEnabled {
    description = "Reconcile prefix-aware VPP IPv6 service publications";
    after = ["vpp.service"];
    requires = ["vpp.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = pkgs.writeShellScript "wait-for-vpp-cli" ''
        for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
          if ${config.services.vpp.package}/bin/vppctl \
               -s /run/vpp/cli.sock show version >/dev/null 2>&1; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "VPP CLI socket did not become ready after 30 seconds" >&2
        exit 1
      '';
      ExecStart = "${ipv6PublicationSync}/bin/vpp-ipv6-publication-sync --policy /etc/vpp/ipv6-publications.json --vppctl ${config.services.vpp.package}/bin/vppctl";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "40s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = ["AF_UNIX"];
      # Linux housekeeping stays on core 0; VPP owns main core 1 and workers
      # 2-7, so a prefix reconciliation cannot steal dataplane time.
      CPUAffinity = "0";
      Nice = 10;
      UMask = "0077";
    };
  };

  systemd.timers.vpp-ipv6-publication-sync = lib.mkIf ipv6PublicationsEnabled {
    description = "Track DHCPv6-PD changes in VPP publication ACLs";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnActiveSec = "2s";
      OnUnitActiveSec = "30s";
      AccuracySec = "1s";
      Unit = "vpp-ipv6-publication-sync.service";
    };
  };

  assertions = [
    {
      assertion = transition.mode == "legacy-flat";
      message = "BlueField cutover closure requires the legacy-flat transition plan.";
    }
    {
      assertion = transition.switch.bluefieldPortMode == "hybrid";
      message = "BlueField cutover requires a hybrid parent interface.";
    }
    {
      assertion = !network.routing.production.firewall.publishIpv6Services || plan.ipv6Publications != [];
      message = "IPv6 publication is enabled but no forward has publishIpv6 = true.";
    }
    {
      assertion = builtins.all (p: p.ipv6Endpoint != null) plan.ipv6Publications;
      message = "Every native IPv6 publication needs a stable endpoint MAC and subnet ID.";
    }
    {
      assertion = builtins.all (p: p.externalPort == p.localPort) plan.ipv6Publications;
      message = "Native IPv6 service publication cannot translate ports.";
    }
    {
      assertion = plan.platform.dataplane.driver == config.bluefield2.vpp.dataplaneDriver;
      message = "The rendered VPP transition plan must use the configured dataplane driver.";
    }
    {
      assertion =
        config.bluefield2.vpp.dataplaneDriver != "dpdk"
        || !(lib.hasInfix "create interface rdma" plan.startupConfig);
      message = "A DPDK transition plan must not contain an RDMA interface creation command.";
    }
  ];
}
