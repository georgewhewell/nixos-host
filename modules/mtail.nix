{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mtail;

  # Build the mtail programs directory from all configured programs
  # Also validate that programs compile correctly
  mtailProgsDir = pkgs.runCommand "mtail-progs" {
    nativeBuildInputs = [ pkgs.mtail ];
  } ''
    mkdir -p $out

    # Write all programs
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: program: ''
      echo "Writing program: ${name}.mtail"
      cat > $out/${name}.mtail << 'EOF'
      ${program}
      EOF
    '') cfg.programs)}

    # Validate compilation
    echo "Validating mtail programs..."

    # Create a dummy log file for compilation test
    touch /tmp/dummy.log

    # Test compilation of all programs
    # mtail --compile_only doesn't actually exit cleanly, so we'll check for compilation errors in the output
    echo "Running: mtail --progs $out --logs /tmp/dummy.log --compile_only"

    # Run mtail with timeout and capture output
    OUTPUT=$(timeout 2 mtail --progs $out --logs /tmp/dummy.log --compile_only --alsologtostderr 2>&1 || true)

    # Check for compilation errors in the output
    if echo "$OUTPUT" | grep -E "compile error|syntax error|parse error" > /dev/null; then
      echo "ERROR: Failed to compile mtail programs:"
      echo "$OUTPUT"
      exit 1
    fi

    # Check that the program was loaded (should see "unmarking" messages for each .mtail file)
    for prog in $out/*.mtail; do
      PROG_NAME=$(basename "$prog")
      if ! echo "$OUTPUT" | grep -q "unmarking $PROG_NAME"; then
        echo "ERROR: Program $PROG_NAME was not loaded. Check for syntax errors."
        echo "$OUTPUT"
        exit 1
      fi
    done

    echo "All mtail programs compiled successfully!"
  '';
in {
  options = {
    services.mtail = {
      enable = lib.mkEnableOption "mtail log processor for metrics extraction";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3903;
        description = ''
          Port for mtail Prometheus metrics endpoint.
        '';
      };

      logs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["/var/log/nginx/access.log" "/var/log/syslog"];
        description = ''
          List of log files or globs for mtail to monitor.
        '';
      };

      programs = lib.mkOption {
        type = lib.types.attrsOf lib.types.lines;
        default = {};
        example = lib.literalExpression ''
          {
            nginx = '''
              counter nginx_requests_total by vhost, method, status
              /^(?P<vhost>\S+) .* "(?P<method>\S+) .* (?P<status>\d{3})/ {
                nginx_requests_total[$vhost][$method][$status]++
              }
            ''';
            syslog = '''
              counter syslog_lines_total by facility, severity
              /^<(?P<pri>\d+)>/ {
                syslog_lines_total[($pri / 8)][($pri % 8)]++
              }
            ''';
          }
        '';
        description = ''
          Attribute set of mtail programs. Each attribute name becomes a .mtl file
          and the value is the mtail program content.
        '';
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--emit_metric_timestamp" "--override_timezone=UTC"];
        description = ''
          Additional command-line flags to pass to mtail.
        '';
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "mtail";
        description = ''
          User under which mtail runs. May need to be changed to access certain log files.
        '';
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "mtail";
        description = ''
          Group under which mtail runs.
        '';
      };

      extraGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["nginx" "systemd-journal"];
        description = ''
          Additional groups for the mtail user to access log files.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to open the firewall for the metrics port.
        '';
      };

      debug = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable verbose debug logging for mtail.
        '';
      };

      journaldUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["xmrig" "nginx"];
        description = ''
          List of systemd units whose journald logs should be streamed to mtail via FIFOs.
          For each unit, a FIFO will be created at /run/mtail-UNIT.fifo and a systemd
          service will stream logs using journalctl.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (let
    # Generate FIFO paths for journald units
    journaldFifos = map (unit: "/run/mtail-${unit}.fifo") cfg.journaldUnits;

    # Combine regular logs with journald FIFOs
    allLogs = cfg.logs ++ journaldFifos;
  in {
    assertions = [
      {
        assertion = allLogs != [];
        message = "services.mtail.logs or services.mtail.journaldUnits must contain at least one entry";
      }
      {
        assertion = cfg.programs != {};
        message = "services.mtail.programs must contain at least one mtail program";
      }
    ];

    # Create FIFOs for journald units
    systemd.tmpfiles.rules = map (unit:
      "p /run/mtail-${unit}.fifo 0644 ${cfg.user} ${cfg.group} -"
    ) cfg.journaldUnits;

    # Create streaming services for each journald unit
    systemd.services = lib.listToAttrs (map (unit: {
      name = "mtail-journal-${unit}";
      value = {
        description = "Stream ${unit} logs to mtail FIFO";
        after = ["${unit}.service" "mtail.service"];
        wantedBy = ["multi-user.target"];
        script = ''
          # Strip ANSI color codes from journald output and stream to FIFO
          ${pkgs.systemd}/bin/journalctl -f -u ${unit} -o cat | \
            ${pkgs.gnused}/bin/sed -u 's/\x1b\[[0-9;]*m//g' > /run/mtail-${unit}.fifo
        '';
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    }) cfg.journaldUnits) // {
      mtail = {
        description = "mtail log metrics extractor";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = ''
            ${pkgs.mtail}/bin/mtail \
              --progs ${mtailProgsDir} \
              --logs ${lib.concatStringsSep "," allLogs} \
              --port ${toString cfg.port} \
              --logtostderr \
              ${lib.optionalString cfg.debug "--alsologtostderr --v=2"} \
              ${lib.concatStringsSep " " cfg.extraFlags}
          '';
          Restart = "always";
          RestartSec = 10;
          User = cfg.user;
          Group = cfg.group;
          SupplementaryGroups = cfg.extraGroups;

          # Security hardening
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;

          # Allow reading configured log paths
          ReadOnlyPaths = allLogs ++ [
            "/var/log"  # Often needed for log rotation detection
          ];
        };
      };
    };

    users.users = lib.mkIf (cfg.user == "mtail") {
      mtail = {
        isSystemUser = true;
        group = cfg.group;
        description = "mtail log processor user";
      };
    };

    users.groups = lib.mkIf (cfg.group == "mtail") {
      mtail = {};
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  });

  meta.maintainers = with lib.maintainers; [];
}