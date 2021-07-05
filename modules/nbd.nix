{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.boot.initrd.nbd;
in
{

  options.boot.initrd.nbd = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable mounting nbd devices in initrd
      '';
    };

    postCommands = mkOption {
      type = types.lines;
      default = ''
      '';
      description = ''
        Commands to run after mounting
      '';
    };

    preCommands = mkOption {
      type = types.lines;
      default = ''
      '';
      description = ''
        Commands to run after mounting
      '';
    };

    devices = mkOption {
      description = ''
        NBD devices to be mounted at startup
      '';
      default = { };
      example = literalExample ''
        { nbd0 = { hostname = "192.168.1.1"; port = 9000; }; }
      '';

      type = with types; attrsOf (submodule {
        options = {
          device = mkOption {
            example = "/dev/nbd0";
            type = types.str;
            description = "Path of the device.";
          };

          hostname = mkOption {
            example = "192.168.1.1";
            type = types.str;
            description = ''
              Hostname of nbd target
            '';
          };

          name = mkOption {
            default = null;
            example = "mysharename";
            type = types.nullOr types.str;
          };

          port = mkOption {
            default = "50000";
            example = 50000;
            type = types.nullOr types.str;
          };
        };
      });
    };
  };

  config = mkIf cfg.enable {
    /* boot.initrd.kernelModules = [ "nbd" ]; */
    boot.initrd.extraUtilsCommands = ''
      copy_bin_and_libs ${pkgs.nbd}/bin/nbd-client
    '';

    boot.initrd.preLVMCommands = mkAfter (
      ''
        ${cfg.preCommands}
        echo "Mounting NBD devices.."
        for o in $(cat /proc/cmdline); do
          case $o in
            nbd.*)
              device=$(echo $o | cut -f1 -d =  | cut -f2 -d .)
              address=$(echo $o | cut -f2 -d = | cut -f1 -d ':')
              port=$(echo $o | cut -f2 -d = | cut -f2 -d ':' | cut -f1 -d '/')
              name=$(echo $o | cut -f2 -d '/')
              echo "Mounting $address:$port/$name on $device"
              nbd-client $address $port /dev/$device \
                -persist \
                -systemd-mark \
                -b 1024 \
                -t 10
            ;;
          esac
        done
        ${cfg.postCommands}
      ''
    );

    boot.kernelParams =
      lib.mapAttrsToList
        (device: conf:
          "nbd.${device}=${conf.hostname}:${conf.port}/${builtins.toString conf.name}")
        cfg.devices;

  };
  meta = { };
}
