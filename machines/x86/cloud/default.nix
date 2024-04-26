{ config, pkgs, lib, modulesPath, consts, ... }:

{

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/headless.nix
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableGraphical = false;
    };
    wireguard = {
      enable = true;
    };
  };

  deployment.targetHost = "78.47.88.127";
  deployment.targetUser = "grw";

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
    networks = {
      "10-wan" = {
        matchConfig.Name = "enp1s0";
        networkConfig.DHCP = "ipv4";
      };
    };
  };

  networking = {
    hostName = "cloud";
    useNetworkd = true;
    nftables.enable = true;

    firewall = {
      checkReversePath = "loose";

      logRefusedConnections = false;
      logRefusedPackets = false;
      logReversePathDrops = true;
      trustedInterfaces = [ "wg0" ];

      interfaces.enp1s0 = {
        allowedTCPPorts = [
          22 # ssh
        ];
        allowedUDPPorts = [
          51820 # wireguard
        ];
      };
    };
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  boot.loader.grub.device = "/dev/sda";
  boot.loader.systemd-boot.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };

  # systemd.services.public-ip-sync-google-clouddns =
  #   let
  #     gcloud-json = pkgs.writeText "credentials.json" pkgs.secrets.domain-owner-terraformer;
  #   in
  #   {
  #     environment = {
  #       CLOUDSDK_CORE_PROJECT = "domain-owner";
  #       CLOUDSDK_COMPUTE_ZONE = "eu-west-1";
  #       GCLOUD_SERVICE_ACCOUNT_KEY_FILE = gcloud-json;
  #       GCLOUD_DNS_ZONE_ID = "satanic-link";
  #     };
  #     script = ''
  #       ${pkgs.public-ip-sync-google-clouddns}/bin/public-ip-sync-google-clouddns.sh -name "cloud.satanic.link."
  #     '';
  #     wantedBy = [ "multi-user.target" ];
  #     serviceConfig = {
  #       Type = "oneshot";
  #       Restart = "no";
  #     };
  #   };

  # systemd.timers.public-ip-sync-google-clouddns = {
  #   partOf = [ "public-ip-sync-google-clouddns.service" ];
  #   wantedBy = [ "multi-user.target" ];
  #   timerConfig = {
  #     OnBootSec = "2min";
  #     OnUnitActiveSec = "3600";
  #   };
  # };

  programs.mosh.enable = true;

  environment.systemPackages = with pkgs; [
    tmux
    htop
    weechat
    wireguard-tools
  ];

  services.tor = {
    enable = true;
    openFirewall = true;
    client = {
      enable = true;
      socksListenAddress = {
        IsolateDestAddr = true;
        addr = "192.168.33.1";
        port = 9090;
      };
    };
  };
}
