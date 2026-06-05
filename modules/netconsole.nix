{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.sconfig.netconsole;
  sender = cfg.sender;
  collector = cfg.collector;

  bool01 = value: if value then "1" else "0";

  senderScript = pkgs.writeShellApplication {
    name = "netconsole-configure";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
      kmod
      util-linux
    ];
    text = ''
      set -euo pipefail

      name=${lib.escapeShellArg sender.name}
      base="/sys/kernel/config/netconsole/$name"

      modprobe configfs || true
      if ! mountpoint -q /sys/kernel/config; then
        mount -t configfs configfs /sys/kernel/config
      fi
      modprobe netconsole netconsole= || true

      if [ ! -d /sys/kernel/config/netconsole ]; then
        echo "netconsole configfs directory is unavailable" >&2
        exit 1
      fi

      if [ -d "$base" ]; then
        echo 0 > "$base/enabled" 2>/dev/null || true
        rmdir "$base" 2>/dev/null || {
          echo 1 > "$base/release" 2>/dev/null || true
          rmdir "$base" 2>/dev/null || true
        }
      fi

      mkdir "$base"
      write_attr() {
        printf '%s' "$2" > "$base/$1"
      }

      write_attr dev_name ${lib.escapeShellArg sender.device}
      write_attr local_ip ${lib.escapeShellArg sender.localIp}
      write_attr local_port ${toString sender.localPort}
      write_attr remote_ip ${lib.escapeShellArg sender.targetIp}
      write_attr remote_port ${toString sender.targetPort}
      write_attr remote_mac ${lib.escapeShellArg sender.targetMac}
      if [ -e "$base/extended" ]; then
        write_attr extended ${bool01 sender.extended}
      fi

      write_attr enabled 1
      echo "nixos netconsole target $name enabled dev=${sender.device} remote=${sender.targetIp}:${toString sender.targetPort}" > /dev/kmsg || true
    '';
  };

  senderCleanupScript = pkgs.writeShellApplication {
    name = "netconsole-cleanup";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = ''
      set -euo pipefail

      name=${lib.escapeShellArg sender.name}
      base="/sys/kernel/config/netconsole/$name"
      if [ ! -d "$base" ]; then
        exit 0
      fi

      echo 0 > "$base/enabled" 2>/dev/null || true
      rmdir "$base" 2>/dev/null || {
        echo 1 > "$base/release" 2>/dev/null || true
        rmdir "$base" 2>/dev/null || true
      }
    '';
  };

  collectorScript = pkgs.writeShellApplication {
    name = "netconsole-collector";
    runtimeInputs = with pkgs; [
      coreutils
      netcat-openbsd
    ];
    text = ''
      set -euo pipefail

      mkdir -p "$(dirname ${lib.escapeShellArg collector.logFile})"
      touch ${lib.escapeShellArg collector.logFile}
      chmod 0644 ${lib.escapeShellArg collector.logFile}

      exec stdbuf -oL nc -u -k -l ${toString collector.port} \
        | stdbuf -oL tee -a ${lib.escapeShellArg collector.logFile}
    '';
  };
in
{
  options.sconfig.netconsole = {
    sender = {
      enable = lib.mkEnableOption "dynamic netconsole sender";
      name = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Configfs target name under /sys/kernel/config/netconsole.";
      };
      device = lib.mkOption {
        type = lib.types.str;
        description = "Network device passed to netconsole, for example eno1.";
      };
      localIp = lib.mkOption {
        type = lib.types.str;
        description = "Local source IPv4 address.";
      };
      localPort = lib.mkOption {
        type = lib.types.port;
        default = 6665;
        description = "Local UDP source port.";
      };
      targetIp = lib.mkOption {
        type = lib.types.str;
        description = "Remote collector IPv4 address.";
      };
      targetPort = lib.mkOption {
        type = lib.types.port;
        default = 6666;
        description = "Remote collector UDP port.";
      };
      targetMac = lib.mkOption {
        type = lib.types.str;
        description = "Remote collector MAC address as seen from the sender.";
      };
      extended = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable netconsole extended console records when supported.";
      };
      panicPrint = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = 63;
        description = "kernel.panic_print value while netconsole sender is enabled.";
      };
      printk = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "kernel.printk value while netconsole sender is enabled.";
      };
    };

    collector = {
      enable = lib.mkEnableOption "UDP netconsole collector";
      port = lib.mkOption {
        type = lib.types.port;
        default = 6666;
        description = "UDP port to listen on.";
      };
      logFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/log/netconsole/netconsole.log";
        description = "File where received netconsole datagrams are appended.";
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open the collector UDP port in the local firewall.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf sender.enable {
      boot.kernel.sysctl =
        lib.optionalAttrs (sender.panicPrint != null) {
          "kernel.panic_print" = lib.mkDefault sender.panicPrint;
        }
        // lib.optionalAttrs (sender.printk != null) {
          "kernel.printk" = lib.mkDefault sender.printk;
        };

      systemd.services.netconsole-sender = {
        description = "Configure dynamic netconsole sender";
        after = [ "network-online.target" "systemd-modules-load.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${senderScript}/bin/netconsole-configure";
          ExecStop = "${senderCleanupScript}/bin/netconsole-cleanup";
        };
      };
    })

    (lib.mkIf collector.enable {
      networking.firewall.allowedUDPPorts =
        lib.mkIf collector.openFirewall [ collector.port ];

      systemd.services.netconsole-collector = {
        description = "Collect UDP netconsole logs";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "2s";
          ExecStart = "${collectorScript}/bin/netconsole-collector";
        };
      };
    })
  ];
}
