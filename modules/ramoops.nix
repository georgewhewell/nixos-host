{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.sconfig.ramoops;
in
{
  options.sconfig.ramoops = {
    enable = lib.mkEnableOption "ramoops/pstore crash capture";

    memAddress = lib.mkOption {
      type = lib.types.str;
      description = "Physical start address of the RAM region reserved for ramoops.";
    };

    memmapSize = lib.mkOption {
      type = lib.types.str;
      default = "2M";
      description = "Size used in the kernel memmap reservation.";
    };

    memSize = lib.mkOption {
      type = lib.types.str;
      default = "0x200000";
      description = "Size passed to ramoops.mem_size.";
    };

    recordSize = lib.mkOption {
      type = lib.types.str;
      default = "0x40000";
      description = "Size of each ramoops dmesg record.";
    };

    maxReason = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Maximum pstore kmsg dump reason: 2 records oops and panic.";
    };

    ecc = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "ECC setting passed to ramoops.ecc.";
    };

    copyDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pstore";
      description = "Directory where pstore records are copied at boot.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "ramoops" ];
    boot.kernelParams = [
      ("memmap=" + cfg.memmapSize + "$" + cfg.memAddress)
      "efi_pstore.pstore_disable=1"
      "pstore.backend=ramoops"
      "ramoops.mem_address=${cfg.memAddress}"
      "ramoops.mem_size=${cfg.memSize}"
      "ramoops.record_size=${cfg.recordSize}"
      "ramoops.console_size=0x0"
      "ramoops.ftrace_size=0x0"
      "ramoops.pmsg_size=0x0"
      "ramoops.max_reason=${toString cfg.maxReason}"
      "ramoops.ecc=${toString cfg.ecc}"
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.copyDirectory} 0700 root root -"
    ];

    systemd.services.pstore-save = {
      description = "Copy pstore crash records to persistent storage";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      path = with pkgs; [
        coreutils
      ];
      script = ''
        set -eu

        src=/sys/fs/pstore
        dest=${lib.escapeShellArg cfg.copyDirectory}
        [ -d "$src" ] || exit 0

        stamp="$(date -u +%Y%m%dT%H%M%SZ)"
        out="$dest/$stamp"
        copied=0
        mkdir -p "$out"

        for f in "$src"/*; do
          [ -e "$f" ] || continue
          cp -a "$f" "$out"/
          copied=1
        done

        if [ "$copied" -eq 0 ]; then
          rmdir "$out"
        fi
      '';
    };
  };
}
