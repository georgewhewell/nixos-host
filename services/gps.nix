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
        Line speed to run the receiver at. gpsd probes the common rates
        itself, but pinning it removes a few seconds of guessing at every
        start and makes a mis-wired or reconfigured module fail loudly
        instead of silently.

        If this differs from `powerOnBaudRate` the receiver is switched to it
        at boot (see `initCommands`); with 1 Hz output, GPS+BeiDou+GLONASS and
        the full NMEA sentence set, 9600 baud overruns and you get truncated
        sentences, so a faster link is a prerequisite for more constellations.
      '';
    };

    powerOnBaudRate = lib.mkOption {
      type = lib.types.ints.positive;
      default = 9600;
      description = ''
        The rate the receiver comes up at after a power cycle, i.e. whatever
        is in its own flash. We deliberately do not persist settings to the
        module (no `$PCAS00`), so configuration lives in this file and is
        re-applied on every boot — which means the module always powers on at
        its factory rate and we talk to it there first.
      '';
    };

    initCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "PCAS04,7" "PCAS11,1" ];
      description = ''
        Vendor sentences sent to the receiver before gpsd starts, written
        WITHOUT the leading `$` and without a checksum — the checksum is
        computed for you, since hand-computed XORs are exactly the sort of
        thing that silently no-ops.

        These are CASIC/`$PCAS` commands (URANUS/Allystar/ATGM336-class
        receivers). Useful ones:
          PCAS04,7   constellations: 1=GPS 2=BDS 3=GPS+BDS 4=GLONASS
                     5=GPS+GLONASS 6=BDS+GLONASS 7=all three
          PCAS11,1   scenario: 0=portable 1=stationary 2=pedestrian
                     3=automotive 4=sea 5=airborne
        `PCAS01` (baud) is generated from `baudRate` instead of being listed
        here, because the speed change has to be sequenced against stty.
      '';
    };

    tools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install cgps/gpsmon/gpspipe and the PPS test utilities.";
    };

    chrony = {
      enable = lib.mkEnableOption "chrony disciplined by gpsd's shared-memory time";

      shmUnit = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = ''
          gpsd's SHM segment to read. gpsd uses units 0/1 when it runs as
          root and 2/3 otherwise, and NixOS runs it as the `gpsd` user — hence
          2 by default. Confirm with `ntpshmmon`, which only shows samples
          once the receiver has a fix.
        '';
      };

      offset = lib.mkOption {
        type = lib.types.str;
        default = "0.100";
        description = ''
          Seconds to add to the SHM timestamp. NMEA time arrives well after
          the second it describes — serialisation plus 9600 baud — so without
          this the clock is dragged late. Only a calibration against a better
          source makes this precise; the default is a conservative guess.
        '';
      };

      servers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "0.nixos.pool.ntp.org" "1.nixos.pool.ntp.org" ];
        description = ''
          Network fallbacks. Kept deliberately: an NMEA-only refclock is a
          coarse source, and a receiver with no fix supplies nothing at all,
          so the host should never depend on it alone.
        '';
      };
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
      extraArgs = [
        # Poll the receiver even with no client attached, so the first
        # consumer gets a warm almanac rather than waiting out a cold start.
        "-n"
        # Tell gpsd the speed instead of letting it autobaud. gpsd opens the
        # device *after* gps-serial-setup has run and probes the line itself,
        # so pinning the tty beforehand achieves nothing — it detected 9600
        # and quietly undid the switch to 115200. Passing -s makes gpsd open
        # at the intended rate and stop hunting.
        "-s"
        (toString cfg.baudRate)
      ];
    };

    # gpsd inherits whatever line discipline the port was left in, and the
    # receiver forgets everything on power loss, so both are (re)established
    # here before gpsd opens the device.
    systemd.services.gps-serial-setup = {
      description = "Configure the GNSS receiver on ${cfg.device} for gpsd";
      before = [ "gpsd.service" ];
      requiredBy = [ "gpsd.service" ];
      # Re-run whenever gpsd restarts. With RemainAfterExit alone this stays
      # latched "active (exited)" forever, so a redeploy that restarts gpsd
      # would leave the receiver unconfigured while gpsd came back with new
      # settings — which is precisely how gpsd ended up opening at a speed the
      # module was not using.
      partOf = [ "gpsd.service" ];
      after = [ "dev-${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/dev/" cfg.device)}.device" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = let
        # $PCAS01 speed codes.
        baudCode = {
          "4800" = 0;
          "9600" = 1;
          "19200" = 2;
          "38400" = 3;
          "57600" = 4;
          "115200" = 5;
        };
        target = toString cfg.baudRate;
        needsSwitch = cfg.baudRate != cfg.powerOnBaudRate;
        # NMEA checksum: XOR of every byte between '$' and '*'. Computed here
        # rather than in shell so a malformed sentence fails evaluation, and
        # so the exact bytes are visible in the built unit.
        sentence = body: let
          ck = lib.foldl (a: c: builtins.bitXor a (lib.strings.charToInt c)) 0
            (lib.stringToCharacters body);
        in "$" + body + "*" + lib.fixedWidthString 2 "0" (lib.toHexString ck);

        # Single-quoted throughout: the shell must not expand `$PCAS…`.
        emit = body: ''
          echo '-> ${sentence body}'
          printf '${sentence body}\r\n' > ${cfg.device}
          sleep 1
        '';
      in
        assert lib.assertMsg (!needsSwitch || baudCode ? ${target})
          "services.gps-receiver.baudRate ${target} has no $PCAS01 speed code";
        ''
          if [ ! -e ${cfg.device} ]; then
            echo "${cfg.device} absent; leaving gpsd to fail loudly"
            exit 0
          fi

          # Always open at the rate the receiver powers on with; anything else
          # talks gibberish to a module that has just cold-started.
          stty -F ${cfg.device} ${toString cfg.powerOnBaudRate} raw -echo -crtscts clocal
        ''
        + lib.optionalString needsSwitch (''
          echo "switching receiver ${toString cfg.powerOnBaudRate} -> ${target} baud"
        ''
        + emit "PCAS01,${toString baudCode.${target}}"
        + ''
          stty -F ${cfg.device} ${target} raw -echo -crtscts clocal
        '')
        + lib.concatMapStrings emit cfg.initCommands;
    };

    # Time. gpsd publishes each fix's timestamp into a SysV shared-memory
    # segment; chrony reads it as a reference clock. Without PPS this is
    # inherently coarse — tens of milliseconds, limited by NMEA serialisation
    # jitter rather than the receiver — so it is a good source, not a
    # stratum-1 one. That needs the PPS line this board has no GPIO for.
    services.chrony = lib.mkIf cfg.chrony.enable {
      enable = true;
      servers = cfg.chrony.servers;
      extraConfig = ''
        # refid GPS so `chronyc sources` names it legibly.
        refclock SHM ${toString cfg.chrony.shmUnit} refid GPS offset ${cfg.chrony.offset} precision 1e-1 poll 4 filter 8

        # The receiver supplies nothing at all until it fixes, and can drop
        # out again on this antenna, so let chrony fall back cleanly rather
        # than wedging on an unreachable refclock.
        makestep 1.0 3
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
