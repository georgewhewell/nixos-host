{mkSecret, config, network, ...}: let
  self = network.hosts."arr-servers";
in {
  # Declare autobrr secret using sops-nix
  sops.secrets.autobrr = mkSecret "autobrr" {};

  systemd.services."container@arr-servers" = {
    bindsTo = ["mnt-Media.mount"];
    after = ["mnt-Media.mount" "sriov-init.service"];
    wants = ["sriov-init.service"];
  };

  containers.arr-servers = {
    autoStart = true;
    privateNetwork = true;
    # Use SR-IOV VF instead of bridge for dedicated hardware NIC
    interfaces = ["enp172s0v0"];

    bindMounts = {
      "/run/autobrr.secret".hostPath = "/run/autobrr.secret";
      "/var/lib/private/autobrr" = {
        hostPath = "/var/lib/autobrr";
        isReadOnly = false;
      };
      "/var/lib/radarr" = {
        hostPath = "/var/lib/radarr";
        isReadOnly = false;
      };
      "/var/lib/sonarr" = {
        hostPath = "/var/lib/sonarr";
        isReadOnly = false;
      };
      "/var/lib/qbittorrent" = {
        hostPath = "/var/lib/qbittorrent";
        isReadOnly = false;
      };
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      imports = [../profiles/container.nix];

      networking.hostName = "arr-servers";

      # Configure the SR-IOV VF interface (override DHCP from container.nix)
      networking.useNetworkd = true;
      networking.interfaces = {};  # Clear legacy interface config
      systemd.network = {
        enable = true;
        networks."10-vf" = {
          matchConfig.Name = "enp172s0v0";
          address = [(network.cidrOf "lan" self.addresses.lan)];
          gateway = [network.routerIp];
          networkConfig = {
            DNS = network.routerIp;
          };
        };
      };

      users.users.radarr.extraGroups = ["qbittorrent"];
      users.users.sonarr.extraGroups = ["qbittorrent"];

      services.radarr = {
        enable = true;
        openFirewall = true;
      };

      services.sonarr = {
        enable = true;
        openFirewall = true;
      };

      services.autobrr = {
        enable = true;
        openFirewall = true;
        secretFile = "/run/autobrr.secret";
        settings = {
          host = "0.0.0.0";
          port = 7474;
        };
      };
    };
  };
}
