{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.strixHalo;
  runtimeCfg = cfg.runtimeAssertions;
  pagesPerGiB = 262144; # 1 GiB / 4 KiB
  mesFirmwareRev = "3d5c8135206cef364e7d353711b3e7358a90d152";
  fetchMesFirmware =
    file: hash:
    pkgs.fetchurl {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/amdgpu/${file}?id=${mesFirmwareRev}";
      inherit hash;
    };
  mesFirmwarePackage = pkgs.runCommand "strix-halo-mes-firmware-0x80" { } ''
    install -Dm644 ${fetchMesFirmware "gc_11_5_0_mes_2.bin" "sha256-XdxUTOMcScfvDxQQyo7oi3KmrARRS9Ec+v/gBJQ5ce0="} \
      "$out/lib/firmware/amdgpu/gc_11_5_0_mes_2.bin"
    install -Dm644 ${fetchMesFirmware "gc_11_5_1_mes_2.bin" "sha256-jgeDLBjYe3ZD/CIWM9hBpfo7rg59Kq0fKyEuGQ+WOgo="} \
      "$out/lib/firmware/amdgpu/gc_11_5_1_mes_2.bin"
  '';
  efiValueAssertionType = lib.types.submodule {
    options = {
      variable = lib.mkOption {
        type = lib.types.str;
        example = "Setup-ec87d643-eba4-4bb5-a1e5-3f3e36b20da9";
        description = "Full efivarfs file name under /sys/firmware/efi/efivars.";
      };
      dataOffset = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 0;
        description = "Offset into EFI variable payload data. The 4-byte efivarfs attribute prefix is skipped automatically.";
      };
      expectedHex = lib.mkOption {
        type = lib.types.str;
        example = "01";
        description = "Expected byte string, encoded as lowercase or uppercase hexadecimal.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable assertion label used in failure output.";
      };
    };
  };
  kernelParamAssertionScript = lib.concatMapStringsSep "\n"
    (
      param: "assert_cmdline_has ${lib.escapeShellArg param}"
    )
    runtimeCfg.assertKernelParams;
  efiValueAssertionScript = lib.concatMapStringsSep "\n"
    (assertion: ''
      assert_efi_value_equals \
        ${lib.escapeShellArg assertion.variable} \
        ${toString assertion.dataOffset} \
        ${lib.escapeShellArg assertion.expectedHex} \
        ${lib.escapeShellArg assertion.description}
    '')
    runtimeCfg.assertEfiValueEquals;
  runtimeAssertionScript = pkgs.writeShellApplication {
    name = "strix-halo-runtime-assertions";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
    ];
    text = ''
      set -euo pipefail

      failed=0

      record_fail() {
        printf 'FAIL: %s\n' "$*" >&2
        failed=1
      }

      record_ok() {
        printf 'ok: %s\n' "$*"
      }

      # May be unused when no extra kernel cmdline assertions are configured.
      # shellcheck disable=SC2329
      assert_cmdline_has() {
        local needle=$1

        if tr ' ' '\n' < /proc/cmdline | grep -Fxq -- "$needle"; then
          record_ok "kernel cmdline contains $needle"
        else
          record_fail "kernel cmdline is missing $needle"
        fi
      }

      # May be unused when hosts deliberately disable IOMMU.
      # shellcheck disable=SC2329
      assert_iommu_enabled() {
        local group_count iommu_count

        if [ ! -d /sys/kernel/iommu_groups ]; then
          record_fail "/sys/kernel/iommu_groups is missing"
          return
        fi

        group_count=$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d | wc -l)
        if [ "$group_count" -gt 0 ]; then
          record_ok "IOMMU groups present ($group_count groups)"
        else
          record_fail "no IOMMU groups are present"
        fi

        if [ ! -d /sys/class/iommu ]; then
          record_fail "/sys/class/iommu is missing"
          return
        fi

        iommu_count=$(find /sys/class/iommu -mindepth 1 -maxdepth 1 -type l | wc -l)
        if [ "$iommu_count" -gt 0 ]; then
          record_ok "IOMMU device present ($iommu_count device(s))"
        else
          record_fail "no IOMMU devices are present"
        fi
      }

      # May be unused on hosts that only enable non-EFI runtime assertions.
      # shellcheck disable=SC2329
      assert_efi_value_equals() {
        local variable=$1
        local data_offset=$2
        local expected_hex=$3
        local label=$4
        local path="/sys/firmware/efi/efivars/$variable"
        local expected length skip actual

        if [ -z "$label" ]; then
          label="$variable@data+$data_offset"
        fi

        expected=$(printf '%s' "$expected_hex" | tr 'A-F' 'a-f')
        case "$expected" in
          ""|*[!0-9a-f]*)
            record_fail "$label: expectedHex must be non-empty hexadecimal, got '$expected_hex'"
            return
            ;;
        esac
        if [ $(( ''${#expected} % 2 )) -ne 0 ]; then
          record_fail "$label: expectedHex must contain whole bytes, got '$expected_hex'"
          return
        fi

        if [ ! -r "$path" ]; then
          record_fail "$label: EFI variable is not readable: $path"
          return
        fi

        length=$(( ''${#expected} / 2 ))
        skip=$(( 4 + data_offset ))
        actual=$(dd if="$path" bs=1 skip="$skip" count="$length" status=none | od -An -tx1 -v | tr -d '[:space:]')

        if [ "$actual" = "$expected" ]; then
          record_ok "$label == 0x$expected"
        else
          record_fail "$label: expected 0x$expected, got 0x$actual"
        fi
      }

      ${kernelParamAssertionScript}
      ${lib.optionalString runtimeCfg.assertIommuEnabled "assert_iommu_enabled"}
      ${efiValueAssertionScript}

      exit "$failed"
    '';
  };
in
{
  options.hardware.strixHalo = {
    enable = lib.mkEnableOption "AMD Ryzen AI Max+ 395 (Strix Halo / gfx1151) tuning";

    gpuMemoryGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 110;
      example = 62;
      description = ''
        Upper bound on GPU-addressable GTT memory, in GiB. Sets
        `ttm.pages_limit` on the kernel cmdline.

        Default 110: tuned for dedicated-inference Strix Halo boxes with
        128 GiB total, leaving ~18 GiB for the OS. Required to fit large
        quantised models (e.g. 92 GiB DS4 Flash Q2_K) in
        device-allocated HIP tensors.
      '';
    };

    mesFirmware0x80 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install uncompressed Strix Halo MES 0x80 firmware blobs ahead of
        distro linux-firmware. MES 0x83 regresses ROCm queue creation on
        gfx1151 with gfxhub CPF page faults.
      '';
    };

    disableCwsr = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable amdgpu compute wave save/restore. Leave off by default; enable
        only as a workaround for ROCm compute preemption instability.
      '';
    };

    tuned = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the tuned daemon with an inference-tuned profile.";
      };
      profile = lib.mkOption {
        type = lib.types.str;
        default = "accelerator-performance";
        example = "throughput-performance";
        description = "Active tuned profile.";
      };
    };

    hugePages = lib.mkOption {
      type = lib.types.enum [
        "never"
        "madvise"
        "always"
      ];
      default = "always";
      description = "Transparent huge pages mode. `always` cuts IOMMU TLB misses on huge model mmaps ~512x.";
    };

    vmMaxMapCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1048576;
      description = "vm.max_map_count. Default (65530) is too low for huge model mmaps.";
    };

    runtimeAssertions = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install and run impure boot/runtime assertions for Strix Halo HIL machines.";
      };
      assertIommuEnabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Assert that the booted kernel exposes IOMMU groups and an IOMMU device.";
      };
      assertKernelParams = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "iommu=pt" ];
        description = "Extra kernel cmdline tokens that must be present at runtime.";
      };
      assertEfiValueEquals = lib.mkOption {
        type = lib.types.listOf efiValueAssertionType;
        default = [ ];
        description = ''
          Impure EFI variable byte assertions. Each assertion reads
          /sys/firmware/efi/efivars/<variable>, skips the 4-byte efivarfs
          attribute prefix, then compares expectedHex at dataOffset.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelParams = [
        "ttm.pages_limit=${toString (cfg.gpuMemoryGiB * pagesPerGiB)}"
        "transparent_hugepage=${cfg.hugePages}"
      ]
      ++ lib.optional cfg.disableCwsr "amdgpu.cwsr_enable=0";

      tmp.useTmpfs = true;

      kernel.sysctl = {
        "vm.max_map_count" = cfg.vmMaxMapCount;
        "kernel.numa_balancing" = 0;
        "vm.swappiness" = 1;
      };
    };

    hardware.firmware = lib.optional cfg.mesFirmware0x80 mesFirmwarePackage;

    # `hipHostRegister` pins large pages; default RLIMIT_MEMLOCK is 64 KiB.
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "soft";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "*";
        type = "hard";
        item = "memlock";
        value = "unlimited";
      }
    ];

    services.tuned = lib.mkIf cfg.tuned.enable {
      enable = true;
      profiles.strix-halo.main.include = cfg.tuned.profile;
    };
    services.power-profiles-daemon.enable = lib.mkIf cfg.tuned.enable false;

    environment.systemPackages = lib.mkIf runtimeCfg.enable [
      runtimeAssertionScript
    ];

    systemd.services.strix-halo-runtime-assertions = lib.mkIf runtimeCfg.enable {
      description = "Strix Halo impure runtime assertions";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${runtimeAssertionScript}/bin/strix-halo-runtime-assertions";
      };
    };

    systemd.services.tuned-set-profile = lib.mkIf cfg.tuned.enable {
      description = "Set TuneD profile";
      after = [ "tuned.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.tuned}/bin/tuned-adm profile ${cfg.tuned.profile}";
      };
    };

    assertions = [
      {
        assertion = cfg.gpuMemoryGiB <= 120;
        message = "hardware.strixHalo.gpuMemoryGiB=${toString cfg.gpuMemoryGiB} leaves under 8 GiB for the OS on a 128 GiB box.";
      }
    ];
  };
}
