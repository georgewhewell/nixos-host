{...}: {
  systemd.services."container@arr-servers" = {
    bindsTo = ["mnt-Home.mount" "mnt-Media.mount"];
    after = ["mnt-Home.mount" "mnt-Media.mount"];
    unitConfig = {
      ConditionPathExists = "/run/autobrr.secret";
    };
  };

  deployment.keys."autobrr.secret" = {
    keyCommand = ["pass" "autobrr.satanic.link"];
    destDir = "/run";
    uploadAt = "pre-activation";
    permissions = "0777";
  };

  containers.arr-servers = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

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
