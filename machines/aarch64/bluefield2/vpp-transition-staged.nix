{
  lib,
  network,
  ...
}: let
  production = network.routing.production;
  transition = production.transition;
  plan = import ./vpp-transition-plan.nix {inherit lib network;};
  occupiedLanHosts =
    lib.concatMap
    (host: lib.optional (host ? addresses && host.addresses ? lan) host.addresses.lan)
    (builtins.attrValues network.hosts);
in {
  # Review artifacts only. Activating the transition requires a separate
  # cut-over module that replaces vpp-lab.nix; these files cannot do that.
  environment.etc = {
    "vpp/transition/startup.conf" = {
      text = plan.startupConfig;
      mode = "0440";
    };
    "vpp/transition/topology.json" = {
      text = plan.topologyJson;
      mode = "0440";
    };
    "vpp/transition/required-plugins.json" = {
      text = builtins.toJSON plan.requiredPlugins;
      mode = "0440";
    };
    "vpp/transition/health-check" = {
      text = plan.healthScript;
      mode = "0550";
    };
  };

  assertions = [
    {
      assertion = !production.enable && !transition.enable;
      message = "Production and transition VPP plans must remain inactive in the staging closure.";
    }
    {
      assertion = transition.mode == "legacy-flat";
      message = "The first gateway handoff must preserve the legacy flat inside network.";
    }
    {
      assertion = transition.switch.bluefieldPortMode == "hybrid";
      message = "The transition needs untagged legacy traffic plus tagged WAN/WiFi on BlueField.";
    }
    {
      assertion = transition.switch.legacyUplink == production.switch.lanFabricTrunk;
      message = "The transition must use the FDB-proved CRS812 to CRS804 uplink.";
    }
    {
      assertion = transition.controlPlane.targetIp != transition.controlPlane.currentGatewayIp;
      message = "The retired router service address must be distinct from VPP's gateway address.";
    }
    {
      assertion = transition.controlPlane.targetHost < network.vlans.lan.dhcp.start;
      message = "The retired router service address must stay outside the DHCP pool.";
    }
    {
      assertion = !(builtins.elem transition.controlPlane.targetHost occupiedLanHosts);
      message = "The retired router service address collides with an existing static LAN host.";
    }
    {
      assertion = builtins.elem "router-control" production.nat44.publicationGroups;
      message = "The VPP handoff must preserve the home WireGuard publication.";
    }
    {
      assertion = !(builtins.elem "arr-servers" network.policies.backupWan.allowedSourceHosts);
      message = "qBittorrent must remain excluded from the phone backup.";
    }
    {
      assertion = production.wans.backup.policy == "control-only" && !production.wans.backup.installDefaultRoute;
      message = "The phone recovery link must remain control-only and must not install a VPP default route.";
    }
    {
      assertion = !(transition ? backupFallback);
      message = "The transition must not contain an automatic phone fallback.";
    }
  ];
}
