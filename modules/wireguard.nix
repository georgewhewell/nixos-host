{ config, pkgs, lib, consts, ... }:


let
  cfg = config.sconfig.wireguard;
in

{

  options.sconfig.wireguard = {
    enable = lib.mkEnableOption "Wireguard Mesh";
  };

  config = lib.mkIf cfg.enable {

    # boot.extraModulePackages = [ config.boot.kernelPackages.wireguard ];

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
          };
          wireguardPeers = (consts.wireguard.makePeerConfig config.networking.hostName);
        };
      };
      networks.wg0 = {
        matchConfig.Name = "wg0";
        address = [
          (consts.wireguard.getIpForHost config.networking.hostName)
        ];
        DHCP = "no";
        # dns = [ "fc00::53" ];
        # ntp = [ "fc00::123" ];
        # gateway = [
        #   "fc00::1"
        #   "10.100.0.1"
        # ];
        networkConfig = {
          IPv6AcceptRA = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

}
