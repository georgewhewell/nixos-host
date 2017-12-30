{config, lib, pkgs, ...}:

with lib;

let
  package = pkgs.pythonPackages.buildPythonApplication rec {
    pname = "undervolt";
    version = "0.1.2";
    name = "${pname}-${version}";
    doCheck = pkgs.pythonPackages.isPy3k;

    src = pkgs.pythonPackages.fetchPypi {
      inherit pname version;
      sha256 = "0236bxjg7c7ypj05j6v1r2f8m66wfhn4p4fdhrps6zi7q4li2cad";
    };
  };
  cfg = config.hardware.undervolt;
in {
    options.hardware.undervolt = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          When enabled, automatically apply undervolts on boot and after resume
        '';
      };

      core = mkOption {
        type = types.int;
        default = null;
        description = ''
          CPU Core (0)
        '';
      };

      gpu = mkOption {
        type = types.int;
        default = null;
        description = ''
          Intel GPU (1)
        '';
      };

      cache = mkOption {
        type = types.int;
        default = null;
        description = ''
          CPU Core (2)
        '';
      };

      uncore = mkOption {
        type = types.int;
        default = null;
        description = ''
          CPU Core (3)
        '';
      };

      analogio = mkOption {
        type = types.int;
        default = null;
        description = ''
          Analog I/O
        '';
      };

      digitalio = mkOption {
        type = types.int;
        default = null;
        description = ''
          Digital I/O
        '';
      };
    };

    config = mkIf cfg.enable {
      environment.systemPackages = [package];
      boot.kernelModules = [ "msr" ];
      systemd.services.undervolt = {
        description = "Apply undervolts";
        wantedBy = [ "multi-user.target" "suspend.target" ];
        after = [ "sleep.target" ];
        script = ''
            ${package}/bin/undervolt -v \
              ${optionalString (cfg.core != null) "--core ${toString cfg.core}"} \
              ${optionalString (cfg.gpu != null) "--gpu ${toString cfg.gpu}"} \
              ${optionalString (cfg.cache != null) "--cache ${toString cfg.cache}"} \
              ${optionalString (cfg.uncore != null) "--uncore ${toString cfg.uncore}"} \
              ${optionalString (cfg.analogio != null) "--analogio ${toString cfg.analogio}"}
          '';
        serviceConfig.Type = "oneshot";
      };
    };
    meta = {};
  }
