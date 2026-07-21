{
  pkgs,
  lib,
  ...
}: let
  screenSharingService = "system/com.apple.screensharing";
  screenSharingSetup = pkgs.writeShellScript "hellas-screen-sharing-setup" ''
    set -eu

    # Load and enable PF before launchd exposes Screen Sharing's wildcard
    # sockets. The persistent launchd override stays disabled between boots,
    # so the listener cannot win a boot-time race against this firewall rule.
    /sbin/pfctl -a com.apple/hellas-screen-sharing \
      -f /etc/pf.anchors/hellas-screen-sharing
    if ! /sbin/pfctl -s info | /usr/bin/grep -q '^Status: Enabled'; then
      /sbin/pfctl -E >/dev/null
    fi

    /bin/launchctl enable ${screenSharingService}
    trap '/bin/launchctl disable ${screenSharingService}' EXIT

    remote_management_kickstart=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
    "$remote_management_kickstart" -configure -allowAccessFor -specifiedUsers -quiet
    "$remote_management_kickstart" -configure -users grw -access -on -privs -ControlObserve -quiet
    "$remote_management_kickstart" -configure -clientopts -setvnclegacy -vnclegacy no -quiet
    "$remote_management_kickstart" -activate -restart -agent -quiet
  '';
in {
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

  # Apple Remote Management backs the built-in Screen Sharing client. PF makes
  # its wildcard IPv4/IPv6 listener loopback-only, requiring an authenticated
  # SSH tunnel. Apple account authentication is limited to grw and legacy VNC
  # password authentication stays disabled.
  environment.etc."pf.anchors/hellas-screen-sharing".text = ''
    # Connect with: ssh -N -L 5901:127.0.0.1:5900 goblin
    pass in quick on lo0 proto tcp from any to any port 5900
    block drop in quick proto tcp from any to any port 5900
  '';
  launchd.daemons.hellas-screen-sharing = {
    command = "${screenSharingSetup}";
    serviceConfig = {
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "/var/log/hellas-screen-sharing.log";
      StandardErrorPath = "/var/log/hellas-screen-sharing.error.log";
    };
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
