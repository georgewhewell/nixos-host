# Option schema for windowsConfigurations.*: a Windows host described in Nix
# and converged by windows/converge.ps1 over the host's OpenSSH server.
#
# There is no Nix *on* Windows here. Nix evaluates this module into a
# desired-state JSON; `nix run .#deploy-<name>` ships it with the pinned
# converger and runs it elevated. WinGet Configuration (DSC) was the first
# choice, but its unit processor runs out of process at medium integrity and
# cannot elevate from a non-interactive SSH session, so machine-level
# resources fail there (verified on win10, 2026-09-23).
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config;

  registryValue = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        example = "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU";
      };
      name = mkOption {type = types.str;};
      type = mkOption {
        type = types.enum ["String" "ExpandString" "DWord" "QWord" "MultiString" "Binary"];
        default = "DWord";
      };
      value = mkOption {type = types.oneOf [types.int types.str];};
    };
  };

  firewallRule = types.submodule ({name, ...}: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      protocol = mkOption {
        type = types.enum ["TCP" "UDP"];
        default = "TCP";
      };
      localPorts = mkOption {type = types.listOf types.port;};
      remoteAddresses = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Source addresses/CIDRs; null allows any.";
      };
    };
  });

  portProxy = types.submodule {
    options = {
      listenAddress = mkOption {type = types.str;};
      listenPort = mkOption {type = types.port;};
      connectAddress = mkOption {type = types.str;};
      connectPort = mkOption {type = types.port;};
    };
  };

  winPackage = types.submodule {
    options = {
      id = mkOption {type = types.str;};
      installerType = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      scope = mkOption {
        type = types.nullOr (types.enum ["machine" "user"]);
        default = "machine";
      };
    };
  };

  service = types.submodule ({name, ...}: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      startupType = mkOption {
        type = types.enum ["Automatic" "Manual" "Disabled"];
        default = "Automatic";
      };
      state = mkOption {
        type = types.nullOr (types.enum ["Running" "Stopped"]);
        default = "Running";
      };
    };
  });

  userFile = types.submodule ({name, ...}: {
    options = {
      target = mkOption {
        type = types.str;
        default = name;
        description = "Path relative to the user's profile directory.";
      };
      text = mkOption {type = types.lines;};
    };
  });

  wslDistro = types.submodule ({name, ...}: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };
      nixosConfiguration = mkOption {
        type = types.nullOr types.raw;
        default = null;
        description = ''
          NixOS-WSL system this distro is imported from on first deploy.
          After that it is an ordinary colmena node.
        '';
      };
      user = mkOption {
        type = types.str;
        description = "Windows account that owns (and imported) the distro.";
      };
      installDir = mkOption {type = types.str;};
      default = mkOption {
        type = types.bool;
        default = false;
      };
      keepAlive = mkOption {
        type = types.bool;
        default = false;
        description = "Keep the distro running from boot, without a logon.";
      };
    };
  });
in {
  options = {
    name = mkOption {
      type = types.str;
      description = "Attribute name of this configuration.";
    };
    hostName = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    deployment = {
      targetHost = mkOption {type = types.str;};
      targetUser = mkOption {type = types.str;};
    };

    networking = {
      ipv4 = mkOption {
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            interfaceAlias = mkOption {
              type = types.str;
              default = "Ethernet";
            };
            address = mkOption {type = types.str;};
            prefixLength = mkOption {type = types.ints.between 0 32;};
            gateway = mkOption {type = types.str;};
            dns = mkOption {type = types.listOf types.str;};
          };
        });
      };
      category = mkOption {
        type = types.attrsOf (types.enum ["Public" "Private"]);
        default = {};
        example = {Ethernet = "Private";};
      };
      firewall = mkOption {
        type = types.attrsOf firewallRule;
        default = {};
      };
      portProxies = mkOption {
        type = types.listOf portProxy;
        default = [];
      };
    };

    registry = mkOption {
      type = types.listOf registryValue;
      default = [];
    };
    services = mkOption {
      type = types.attrsOf service;
      default = {};
    };
    packages = mkOption {
      type = types.listOf (types.coercedTo types.str (id: {inherit id;}) winPackage);
      default = [];
      description = ''
        winget packages, by identifier or with installer options. MSIX
        installers cannot be deployed from a non-interactive session
        (0x80073D19), so packages whose default installer is MSIX need an
        explicit `installerType` (e.g. "wix").
      '';
    };

    openssh.adminAuthorizedKeys = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Contents of administrators_authorized_keys; null leaves it alone.";
    };

    users = mkOption {
      default = {};
      type = types.attrsOf (types.submodule {
        options = {
          profileDir = mkOption {type = types.str;};
          files = mkOption {
            type = types.attrsOf userFile;
            default = {};
          };
        };
      });
    };

    wsl.distros = mkOption {
      type = types.attrsOf wslDistro;
      default = {};
    };

    build = {
      state = mkOption {
        type = types.raw;
        readOnly = true;
      };
      bundle = mkOption {
        type = types.package;
        readOnly = true;
      };
      deploy = mkOption {
        type = types.package;
        readOnly = true;
      };
    };
  };

  config.build = let
    winPath = lib.replaceStrings ["/"] ["\\"];
    wslDistros = lib.attrValues cfg.wsl.distros;
    # Relative to C:/ProgramData/nix-windows (see converge.ps1).
    tarballName = d: "wsl-images/${d.name}.wsl";
  in {
    state = {
      inherit (cfg) hostName registry packages;
      networkCategories =
        lib.mapAttrsToList (interfaceAlias: category: {inherit interfaceAlias category;})
        cfg.networking.category;
      services = lib.attrValues cfg.services;
      firewall = lib.attrValues cfg.networking.firewall;
      portProxies = cfg.networking.portProxies;
      ipv4 = cfg.networking.ipv4;
      adminAuthorizedKeys = cfg.openssh.adminAuthorizedKeys;
      files = lib.concatMap (u:
        lib.mapAttrsToList (_: f: {
          path = winPath "${u.profileDir}\\${f.target}";
          inherit (f) text;
        })
        u.files)
      (lib.attrValues cfg.users);
      wsl =
        map (d: {
          inherit (d) name user installDir default keepAlive;
          tarball =
            if d.nixosConfiguration == null
            then null
            else tarballName d;
        })
        wslDistros;
    };

    bundle = pkgs.runCommand "windows-${cfg.name}-bundle" {
      state = builtins.toJSON cfg.build.state;
      passAsFile = ["state"];
    } ''
      mkdir $out
      cp $statePath $out/state.json
      cp ${./converge.ps1} $out/converge.ps1
    '';

    deploy = pkgs.writeShellApplication {
      name = "deploy-${cfg.name}";
      runtimeInputs = [pkgs.openssh pkgs.coreutils];
      text = ''
        # Usage: deploy-${cfg.name} [--dry-run] [--wsl-image] [--target-host H]
        #   --dry-run        show what would change
        #   --wsl-image      build and ship the NixOS-WSL import image(s) (first
        #                    install only; afterwards the distro is a colmena node)
        #   --target-host H  reach the host at H (e.g. before its static IP)
        dry=; wsl_image=; host=${lib.escapeShellArg cfg.deployment.targetHost}
        while (($#)); do
          case $1 in
            --dry-run) dry=-DryRun ;;
            --wsl-image) wsl_image=1 ;;
            --target-host) host=$2; shift ;;
            *) echo "unknown argument: $1" >&2; exit 2 ;;
          esac
          shift
        done

        target=${lib.escapeShellArg cfg.deployment.targetUser}@$host
        bundle=${cfg.build.bundle}
        remote="C:/ProgramData/nix-windows/$(basename "$bundle")"
        ssh=(ssh -o BatchMode=yes "$target")

        "''${ssh[@]}" "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force '$remote' | Out-Null\""
        scp -q -o BatchMode=yes "$bundle/state.json" "$bundle/converge.ps1" "$target:$remote/"

        if [[ -n $wsl_image ]]; then
          work=$(mktemp -d "''${XDG_CACHE_HOME:-$HOME/.cache}/deploy-${cfg.name}.XXXXXX")
          trap 'rm -rf "$work"' EXIT
          ${lib.concatMapStrings (d:
          lib.optionalString (d.nixosConfiguration != null) ''
            echo "building NixOS-WSL image for ${d.name} (needs sudo)" >&2
            sudo ${d.nixosConfiguration.config.system.build.tarballBuilder}/bin/nixos-wsl-tarball-builder "$work/${d.name}.wsl"
            "''${ssh[@]}" "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force 'C:/ProgramData/nix-windows/wsl-images' | Out-Null\""
            scp -q -o BatchMode=yes "$work/${d.name}.wsl" "$target:C:/ProgramData/nix-windows/${tarballName d}"
          '')
        wslDistros}
        fi

        "''${ssh[@]}" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"$remote/converge.ps1\" $dry"

        # Old bundles are only useful for debugging; keep the last three.
        "''${ssh[@]}" "powershell -NoProfile -Command \"Get-ChildItem C:/ProgramData/nix-windows -Directory -Filter *-bundle | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Recurse -Force\"" || true
      '';
    };
  };
}
