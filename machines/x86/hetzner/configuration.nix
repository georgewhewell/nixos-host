{ config, pkgs, lib, modulesPath, ... }:

{

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/headless.nix
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    deployment.targetHost = "78.47.88.127";
    deployment.targetUser = "grw";
    deployment.substituteOnDestination = true;

    networking= {
      hostId = "deadbeef";
      hostName = "cloud";
      firewall = {
        allowedUDPPorts = [
          51820
        ];
        interfaces.wg0 = {
          allowedTCPPorts = [ 9090 ];
        };
      };
    };

    services.consul.enable = lib.mkForce false;

    boot.loader.grub.device = "/dev/sda";
    boot.loader.systemd-boot.enable = false;
    boot.kernelPackages = pkgs.linuxPackages_latest;

    fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };

    systemd.services.public-ip-sync-google-clouddns = let
      gcloud-json = pkgs.writeText "credentials.json" pkgs.secrets.domain-owner-terraformer;
    in {
      environment = {
        CLOUDSDK_CORE_PROJECT = "domain-owner";
        CLOUDSDK_COMPUTE_ZONE = "eu-west-1";
        GCLOUD_SERVICE_ACCOUNT_KEY_FILE = gcloud-json;
        GCLOUD_DNS_ZONE_ID = "satanic-link";
      };
      script = ''
        ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "cloud.satanic.link."
      '';
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "no";
      };
    };

    systemd.timers.public-ip-sync-google-clouddns = {
      partOf = [ "public-ip-sync-google-clouddns.service" ];
      wantedBy = [ "multi-user.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "3600";
      };
    };

    programs.mosh.enable = true;

    environment.systemPackages = with pkgs; [
      tmux htop
      weechat wireguard
    ];

    services.tor = {
      enable = true;
      openFirewall = true;
      client = {
        enable = true;
        socksListenAddress = {
          IsolateDestAddr = true;
          addr = "192.168.24.2";
          port = 9090;
        };
      };
    };

    networking.wireguard = {
      interfaces = {
        "wg0" = {
          ips = [ "192.168.24.2/24" ];
          listenPort = 51820;
          privateKey = pkgs.secrets.wg-hetzner-priv;
          postSetup = ''
            ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 192.168.24.0/24 -o enp1s0 -j MASQUERADE
          '';
          postShutdown = ''
            ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 192.168.24.0/24 -o enp1s0 -j MASQUERADE
          '';
          peers = [
            {
              publicKey = pkgs.secrets.wg-router-pub;
              allowedIPs = [ "192.168.23.0/24" "192.168.24.0/24" ];
              endpoint = "home.satanic.link:51820";
              persistentKeepalive = 25;
            }
          ];
        };
      };
    };

}
