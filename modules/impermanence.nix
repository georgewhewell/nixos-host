{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.sconfig.impermanence;

  seedLine = kind: path: "seed_persist_${kind} ${lib.escapeShellArg path}";

  seedExistingState = ''
    same_persist_target() {
      [ -e "$1" ] && [ -e "$2" ] \
        && [ "$(${pkgs.coreutils}/bin/stat -Lc '%d:%i' "$1")" = "$(${pkgs.coreutils}/bin/stat -Lc '%d:%i' "$2")" ]
    }

    seed_persist_dir() {
      src="$1"
      dst="${cfg.persistentStoragePath}$src"

      if same_persist_target "$src" "$dst"; then
        return
      fi

      if [ -d "$src" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$dst"
        if [ -z "$(${pkgs.coreutils}/bin/ls -A "$dst" 2>/dev/null)" ]; then
          ${pkgs.coreutils}/bin/chown --reference="$src" "$dst"
          ${pkgs.coreutils}/bin/chmod --reference="$src" "$dst"
          ${pkgs.coreutils}/bin/cp -a "$src"/. "$dst"/
        fi
      fi
    }

    seed_persist_file() {
      src="$1"
      dst="${cfg.persistentStoragePath}$src"

      if same_persist_target "$src" "$dst"; then
        return
      fi

      if [ -e "$src" ] && [ ! -e "$dst" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dst")"
        ${pkgs.coreutils}/bin/cp -a "$src" "$dst"
      fi

      if [ -e "$dst" ] && [ -f "$src" ] && [ ! -L "$src" ] \
        && ! ${pkgs.util-linux}/bin/findmnt --mountpoint "$src" >/dev/null 2>&1 \
        && [ -s "$src" ]; then
        backup="$src.pre-impermanence"
        if [ ! -e "$backup" ]; then
          ${pkgs.coreutils}/bin/cp -a "$src" "$backup"
        fi
        : > "$src"
      fi
    }

    ${lib.concatMapStringsSep "\n" (seedLine "dir") cfg.seedExisting.directories}
    ${lib.concatMapStringsSep "\n" (seedLine "file") cfg.seedExisting.files}
  '';
in {
  options.sconfig.impermanence = {
    enable = lib.mkEnableOption "impermanent host state declarations";

    persistentStoragePath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "Persistent storage root used by impermanence bind mounts.";
    };

    hideMounts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hide impermanence bind mounts from desktop file managers.";
    };

    seedExisting = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Copy explicitly listed existing state into persistent storage before first bind mount.";
      };

      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Existing directories to seed into persistent storage on first activation.";
      };

      files = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Existing files to seed into persistent storage on first activation.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # On impermanent hosts, keep logs in the runtime filesystem instead of
    # creating boot-local journals under the ephemeral root.
    # The NanoKVM-derived boards still use a package set without settings.
    services.journald = if options.services.journald ? settings then {
      settings.Journal.Storage = lib.mkDefault "volatile";
    } else {
      storage = lib.mkDefault "volatile";
    };

    environment.persistence.${cfg.persistentStoragePath} = {
      directories = [
        "/var/lib/nixos"
      ];

      files = [
        "/etc/machine-id"
        "/var/lib/systemd/random-seed"
      ];
    };

    sconfig.impermanence.seedExisting = {
      directories = [
        "/var/lib/nixos"
      ];

      files = [
        "/etc/machine-id"
        "/var/lib/systemd/random-seed"
      ];
    };

    system.activationScripts.createPersistentStorageDirs.text =
      lib.mkIf cfg.seedExisting.enable (lib.mkBefore seedExistingState);
  };
}
