{ config, pkgs, lib, consts, ... }:


let
  cfg = config.sconfig.wireguard;
in

{

  options.sconfig.wireguard = {
    enable = lib.mkEnableOption "Wireguard Mesh";
  };

  config = lib.mkIf cfg.enable {

    # allow systemd-networkd to access keys dir
    users.users."systemd-network".extraGroups = [ "keys" ];

    deployment.keys = let hostName = config.networking.hostName; in {
      "wg-${hostName}.secret" =
        {
          keyCommand = [ "pass" "wg-${hostName}" ];
          user = "systemd-network";
          group = "systemd-network";
          destDir = "/run/keys";
          uploadAt = "pre-activation";
        };
    };

    systemd.network = {
      enable = true;
      netdevs = {
        "15-wg0" = {
          netdevConfig = {
            Kind = "wireguard";
            Name = "wg0";
            MTUBytes = "1300";
          };
          # See also man systemd.netdev (also contains info on the permissions of the key files)
          wireguardConfig = {
            # Don't use a file from the Nix store as these are world readable. Must be readable by the systemd.network user
            PrivateKeyFile = "/run/keys/wg-${config.networking.hostName}.secret";
            ListenPort = 51820;
            FirewallMark = 34952;
          };
          wireguardPeers = (consts.wireguard.makePeerConfig config.networking.hostName);
        };
      };
      networks."15-wg0" = {
        matchConfig.Name = "wg0";
        address = [
          (consts.wireguard.getIpForHost config.networking.hostName)
        ];
        DHCP = "no";
        dns = [ "8.8.8.8" ];
        # ntp = [ "fc00::123" ];
        # gateway = [
        #   # "fc00::1"
        #   "192.168.33.1"
        # ];
        networkConfig = {
          IPMasquerade = "ipv4";
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

}
