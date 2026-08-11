{ config, lib, pkgs, ... }:

# gpsd for a directly attached GNSS receiver.
#
# History worth keeping: this used to live on rock-5b, pointed at
# `tcp://esp32-p4-eth-01:8888` — an ESP32 bridging the receiver's UART to TCP,
# because no host had a spare serial port. The receiver now hangs off k3's
# on-board UART, so gpsd talks to the device directly and the ESP32 bridge is
# gone. Keeping this as a module rather than inlining it in the host config
# means the next move is a two-line change, not another archaeology session.
let
  cfg = config.services.gps-receiver;
in
{
  options.services.gps-receiver = {
    enable = lib.mkEnableOption "gpsd for a locally attached GNSS receiver";

    device = lib.mkOption {
      type = lib.types.str;
      example = "/dev/ttyS0";
      description = "Serial device the receiver is wired to.";
    };

    baudRate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 9600;
      description = ''
        Line speed of the receiver. gpsd probes the common rates itself, but
        pinning it removes a few seconds of guessing at every start and makes
        a mis-wired or reconfigured module fail loudly instead of silently.
      '';
    };

    tools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install cgps/gpsmon/gpspipe and the PPS test utilities.";
    };

    exporter = {
      enable = lib.mkEnableOption "Prometheus exporter for gpsd (per-satellite SNR, fix state)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 9015;
        description = "Port to serve metrics on (upstream's default).";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address to bind the metrics endpoint to.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the metrics port in the firewall.";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "--pps-histogram" "--offset-from-geopoint" "--geopoint-lat" "47.37" ];
        description = ''
          Extra flags. `--pps-histogram` needs a PPS source, which this board
          has no wired GPIO for; `--offset-from-geopoint` wants a surveyed
          reference position and only means anything once the receiver fixes.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.gpsd = {
      enable = true;
      devices = [ cfg.device ];
      readonly = false;
      # Poll the receiver even with no client attached, so the first consumer
      # gets a warm almanac rather than waiting out a cold start.
      extraArgs = [ "-n" ];
    };

    # gpsd inherits whatever line discipline the port was left in. Set it once,
    # before gpsd opens the device, so a stale speed from a previous user (or a
    # getty that once owned the port) can't make the receiver look dead.
    systemd.services.gps-serial-setup = {
      description = "Pin ${cfg.device} to ${toString cfg.baudRate} baud for gpsd";
      before = [ "gpsd.service" ];
      requiredBy = [ "gpsd.service" ];
      after = [ "dev-${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/dev/" cfg.device)}.device" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ ! -e ${cfg.device} ]; then
          echo "${cfg.device} absent; leaving gpsd to fail loudly"
          exit 0
        fi
        stty -F ${cfg.device} ${toString cfg.baudRate} raw -echo -crtscts clocal
      '';
    };

    environment.systemPackages = lib.optionals cfg.tools (with pkgs; [
      gpsd # cgps, gpsmon, gpspipe
      pps-tools # ppstest, ppswatch
    ]);

    # Metrics. The exporter is a plain gpsd client over TCP 2947, so it needs
    # no device access of its own — hence DynamicUser and no supplementary
    # groups. It exports per-satellite SNR/elevation/azimuth, satellites seen
    # versus used, and fix mode, which is what makes "tracking but never
    # fixing" visible instead of a mystery.
    systemd.services.gpsd-prometheus-exporter = lib.mkIf cfg.exporter.enable {
      description = "Prometheus exporter for gpsd";
      after = [ "gpsd.service" ];
      wants = [ "gpsd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe pkgs.gpsd-prometheus-exporter)
          "-H"
          "127.0.0.1"
          "-p"
          "2947"
          "-E"
          (toString cfg.exporter.port)
          "-L"
          cfg.exporter.listenAddress
        ]
        ++ cfg.exporter.extraArgs);
        DynamicUser = true;
        Restart = "always";
        # gpsd may still be opening the device on a cold boot; don't hammer it.
        RestartSec = "10s";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      };
    };

    networking.firewall.allowedTCPPorts =
      lib.mkIf (cfg.exporter.enable && cfg.exporter.openFirewall) [ cfg.exporter.port ];
  };
}
