{ config, lib, pkgs, boot, networking, containers, ... }:

{
  fileSystems."/var/lib/hydra" =
    { device = "fpool/root/hydra";
      fsType = "zfs";
    };

  containers.hydra = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/hydra" = {
        hostPath = "/var/lib/hydra";
        isReadOnly = false;
      };
    };

    config = {
      boot.isContainer = true;

      networking.hostName = "hydra";
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.allowedTCPPorts = [ 3000 ];

      require = [ ../hydra/hydra-module.nix ];
services.hydra = {
  enable = true;
  package = (import ../hydra/release.nix {}).build {
    system = pkgs.stdenv.system;
  };
  logo = ./logo.png;
  dbi = "dbi:Pg:dbname=hydra;host=localhost;user=hydra;";
  hydraURL = "http://hydra.4a";
  notificationSender = "yes@itsme.com";
};

      serviceConfig = {
        Type = "simple";
        User = "radarr";
        Group = "nogroup";
        PermissionsStartOnly = "true";
        ExecStart = "${pkgs.radarr}/bin/Radarr";
        Restart = "on-failure";
      };
    };

    users.extraUsers.radarr = {
      home = "/var/lib/radarr";
      group = "radarr";
    };

    };
  };
}
