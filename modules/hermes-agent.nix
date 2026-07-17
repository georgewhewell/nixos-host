{ config, inputs, lib, pkgs, ... }:
let
  cfg = config.services.hermes-agent;
  system = pkgs.stdenv.hostPlatform.system;
  hasInputPackage =
    inputs ? nix-ai-tools
    && inputs.nix-ai-tools ? packages
    && builtins.hasAttr system inputs.nix-ai-tools.packages
    && builtins.hasAttr "hermes-agent" inputs.nix-ai-tools.packages.${system};
in
{
  options.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent messaging gateway";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Hermes Agent package to run. If unset, the package from the
        nix-ai-tools flake input is used for the host platform.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes-agent";
      description = "User that runs the Hermes gateway service.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hermes-agent";
      description = "Group that runs the Hermes gateway service.";
    };

    createUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create the service user.";
    };

    createGroup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create the service group.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes-agent";
      description = "Hermes home directory used for config, state, and logs.";
    };

    stateDirMode = lib.mkOption {
      type = lib.types.str;
      default = "0700";
      description = "Mode for the Hermes home directory.";
    };

    homeDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "HOME for the service process. Defaults to stateDir.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the gateway process.";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      description = "Environment files loaded by systemd for gateway secrets.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        bash
        coreutils
        curl
        findutils
        git
        gnugrep
        gnused
        openssh
        ripgrep
        which
      ];
      description = "Packages added to PATH for Hermes gateway tools.";
    };

    acceptHooks = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pass --accept-hooks to headless gateway runs.";
    };

    replace = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass --replace so the service replaces stale gateway processes.";
    };

    verbose = lib.mkOption {
      type = lib.types.ints.between 0 2;
      default = 0;
      description = "Gateway stderr verbosity: 0 is warnings, 1 is info, 2 is debug.";
    };

    quiet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pass --quiet to suppress gateway stderr logging.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments appended to hermes gateway run.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      package =
        if cfg.package != null
        then cfg.package
        else if hasInputPackage
        then inputs.nix-ai-tools.packages.${system}.hermes-agent
        else throw "services.hermes-agent.package must be set when inputs.nix-ai-tools.packages.${system}.hermes-agent is unavailable.";
      homeDir = if cfg.homeDir != null then cfg.homeDir else cfg.stateDir;
      verboseArgs = lib.genList (_: "-v") cfg.verbose;
      gatewayArgs =
        [
          (lib.getExe package)
          "gateway"
          "run"
        ]
        ++ lib.optional cfg.replace "--replace"
        ++ verboseArgs
        ++ lib.optional cfg.quiet "--quiet"
        ++ lib.optional cfg.acceptHooks "--accept-hooks"
        ++ cfg.extraArgs;
    in
    {
      assertions = [
        {
          assertion = cfg.package != null || hasInputPackage;
          message = "services.hermes-agent.package must be set when inputs.nix-ai-tools.packages.${system}.hermes-agent is unavailable.";
        }
      ];

      users.groups = lib.mkIf cfg.createGroup {
        "${cfg.group}" = { };
      };

      users.users = lib.mkIf cfg.createUser {
        "${cfg.user}" = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.stateDir;
          createHome = true;
        };
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir} ${cfg.stateDirMode} ${cfg.user} ${cfg.group} - -"
      ];

      systemd.services.hermes-gateway = {
        description = "Hermes Agent messaging gateway";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = cfg.extraPackages;
        unitConfig.RequiresMountsFor = [ cfg.stateDir ];
        environment =
          {
            HOME = homeDir;
            USER = cfg.user;
            LOGNAME = cfg.user;
            HERMES_HOME = cfg.stateDir;
            HERMES_HOME_MODE = cfg.stateDirMode;
          }
          // cfg.environment;
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = lib.escapeShellArgs gatewayArgs;
          WorkingDirectory = cfg.stateDir;
          Restart = "always";
          RestartSec = "5s";
          RestartForceExitStatus = 75;
          KillMode = "mixed";
          KillSignal = "SIGTERM";
          ExecReload = "${pkgs.coreutils}/bin/kill -USR1 $MAINPID";
          TimeoutStopSec = "210s";
          UMask = "0077";
          StandardInput = "null";
          StandardOutput = "journal";
          StandardError = "journal";
          EnvironmentFile = lib.mkIf (cfg.environmentFiles != [ ]) cfg.environmentFiles;
        };
      };
    }
  );
}
