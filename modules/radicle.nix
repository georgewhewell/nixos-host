{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.services.radicle;
in
{
  options.services.radicle = {
    enable = lib.mkEnableOption "radicle";
    listen = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The address to listen on";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/radicle";
      description = "The directory to store radicle data";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ inputs.radicle.packages.${pkgs.system}.radicle-cli ];
    networking.firewall.allowedTCPPorts = [ 8776 ];
    systemd.services.radicle-httpd = {
      description = "Radicle HTTP daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.git ];
      serviceConfig = {
        ExecStart = "${inputs.radicle.packages.${pkgs.system}.radicle-httpd}/bin/radicle-httpd ${if cfg.listen != null then "--listen " + cfg.listen else ""}";
        User = "radicle";
        Group = "radicle";
        Restart = "on-failure";
      };
    };

    systemd.services.radicle-node = {
      description = "Radicle Node";
      after = [
        "network.target"
      ];
      wantedBy = [
        "multi-user.target"
      ];
      path = [ pkgs.git ];
      serviceConfig = {
        ExecStart = "${inputs.radicle.packages.${pkgs.system}.radicle-node}/bin/radicle-node";
        User = "radicle";
        Group = "radicle";
        Restart = "on-failure";
      };
    };

    users.groups.radicle = { };
    users.users.radicle = {
      isSystemUser = true;
      group = "radicle";
      home = cfg.dataDir;
      packages = [ pkgs.git inputs.radicle.packages.${pkgs.system}.radicle-cli ];
    };
  };
}
