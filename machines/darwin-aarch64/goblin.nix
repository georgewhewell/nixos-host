{lib, ...}: {
  imports = [
    ./darwin-configuration.nix
    ../../profiles/darwin-no-power-management.nix
    ../../services/hydra-builder-slave-darwin.nix
  ];

  networking.hostName = "goblin";
  ids.gids.nixbld = 350;
  environment.enableAllTerminfo = lib.mkForce false;

  # Disable TCP segmentation offload. macOS bridge0 forwards TSO super-frames
  # (up to 14480 bytes) over Thunderbolt to the router, which can't bridge
  # them to the 25G LAN (MTU 9000) — most jumbo segments get silently dropped
  # and TCP collapses to ~35 Mbps with massive retransmits. Turning TSO off
  # forces TCP to size segments by MSS, restoring ~11 Gbps to the LAN.
  environment.etc."sysctl.conf".text = ''
    net.inet.tcp.tso=0
  '';
}
