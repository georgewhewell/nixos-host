{
  lib,
  network,
  ...
}: let
  production = network.routing.production;
  plan = import ./vpp-production-plan.nix {inherit lib network;};
in {
  # Ship reviewable, generated cut-over artifacts in the BlueField closure.
  # They are deliberately not services and are never fed to the running VPP.
  environment.etc = {
    "vpp/production/startup.conf" = {
      text = plan.startupConfig;
      mode = "0440";
    };
    "vpp/production/topology.json" = {
      text = plan.topologyJson;
      mode = "0440";
    };
    "vpp/production/required-plugins.json" = {
      text = builtins.toJSON plan.requiredPlugins;
      mode = "0440";
    };
    "vpp/production/health-check" = {
      text = plan.healthScript;
      mode = "0550";
    };
  };

  assertions = [
    {
      assertion = !production.enable;
      message = ''
        network.routing.production.enable is a cut-over gate, not a deploy
        toggle. The staged VPP plan must first replace vpp-lab.nix in a
        dedicated, outage-reviewed activation module.
      '';
    }
    {
      assertion = production.wans.backup.installDefaultRoute == false;
      message = "The phone backup must remain control-only without a VPP default route.";
    }
    {
      assertion = !(builtins.elem "arr-servers" network.policies.backupWan.allowedSourceHosts);
      message = "arr-servers/qBittorrent must never enter the phone-backup source allowlist.";
    }
    {
      assertion = production.wans.primary.switchAccessPort != production.switch.bluefieldTrunk;
      message = "Primary ISP access and BlueField trunk must be distinct CRS812 ports.";
    }
  ];
}
