{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./darwin-configuration.nix
    ../../profiles/darwin-no-power-management.nix
    ../../services/hydra-builder-slave-darwin.nix
  ];

  networking.hostName = "goblin";
  ids.gids.nixbld = 350;
  environment.enableAllTerminfo = lib.mkForce false;

  # Goblin is an unattended desktop/build host: bring it back after an outage
  # or a system freeze instead of leaving it powered off until someone visits.
  power = {
    restartAfterPowerFailure = lib.mkForce true;
    restartAfterFreeze = lib.mkForce true;
  };

  sconfig.xmrig = {
    enable = true;
    package = pkgs.xmrig;
    rigId = "goblin";
    httpApi.accessToken = "xmrig";
    inhibit.nixBuilds.enable = true;
    mqttSwitch.passwordFile = "/Users/grw/.config/xmrig/mosquitto-password";
  };

  # Disable TCP segmentation offload. macOS bridge0 forwards TSO super-frames
  # (up to 14480 bytes) over Thunderbolt to the router, which can't bridge
  # them to the 25G LAN (MTU 9000) — most jumbo segments get silently dropped
  # and TCP collapses to ~35 Mbps with massive retransmits. Turning TSO off
  # forces TCP to size segments by MSS, restoring ~11 Gbps to the LAN.
  environment.etc."sysctl.conf".text = ''
    net.inet.tcp.tso=0
  '';
}
