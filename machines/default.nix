nixosModule: inputs: mkSecret: network: pkgsFns:
let
  inherit (inputs.nixpkgs) lib;
  inherit (pkgsFns) pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmStrixHalo pkgsForRocmZnver5 allOverlays;

  # Base system builder - no GPU acceleration
  sys = system: machine:
    let
      pkgs = pkgsFor system;
    in
    lib.nixosSystem {
      inherit system pkgs;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  sysWithSpecialArgs = system: extraSpecialArgs: machine:
    let
      pkgs = pkgsFor system;
    in
    lib.nixosSystem {
      inherit system pkgs;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      } // extraSpecialArgs;
    };

  # Cross-compilation builder - builds on x86_64 for aarch64
  sysCross = machine:
    lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        {
          nixpkgs.buildPlatform = "x86_64-linux";
          nixpkgs.hostPlatform = "aarch64-linux";
          nixpkgs.overlays = allOverlays;
          nixpkgs.config = {
            allowUnfree = true;
            allowBroken = true;
          };
        }
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  # CUDA-enabled system builder for NVIDIA machines
  sysCuda = system: machine:
    let
      pkgs = pkgsForCuda system;
    in
    lib.nixosSystem {
      inherit system pkgs;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  # ROCm-enabled system builder for AMD GPU machines. Takes the
  # `pkgs` instance to use as an arg (so callers can swap between
  # the stock `pkgsForRocm` and the znver5-rebuilt
  # `pkgsForRocmZnver5` per-machine).
  mkRocmSystem = pkgs: machine:
    lib.nixosSystem {
      inherit pkgs;
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  sysRocm = system: machine: mkRocmSystem (pkgsForRocm system) machine;
  sysRocmStrixHalo = system: machine: mkRocmSystem (pkgsForRocmStrixHalo system) machine;
  sysRocmZnver5 = system: machine: mkRocmSystem (pkgsForRocmZnver5 system) machine;

  # RISC-V (Sipeed NanoKVM / SG2002): a regular fleet member. The
  # board's hardware/boot stack (cross pins, kernel, DTB, SD image,
  # nanokvm services) comes from the nanokvm flake as a plain module
  # (`nixosModules.boards.pcie.mainline.sd`), composed with the same
  # shared `nixosModule` base every other host gets. The board module
  # pins nixpkgs host/buildPlatform itself (x86_64 → riscv64 cross),
  # so no `pkgs`/system is passed here. The machine file imports the
  # lightweight `profiles/fleet-core.nix` rather than common.nix —
  # 256 MB has no room for enableAllFirmware and friends.
  sysRiscvNanokvm = machine:
    lib.nixosSystem {
      modules = [
        { _module.args = inputs; }
        inputs.nanokvm.nixosModules.boards.pcie.mainline.sd
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  # RISC-V SpacemiT K3 Pico-ITX. The reusable board support, kernel,
  # firmware, and cross-platform setup come from the nanokvm flake; this
  # builder adds the fleet base and disko module.
  sysRiscvK3 = machine:
    lib.nixosSystem {
      modules = [
        {
          nixpkgs.overlays = allOverlays;
        }
        { _module.args = inputs; }
        inputs.disko.nixosModules.disko
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  strixInstaller = { config, pkgs, lib, inputs, ... }:
    let
      repoSource = builtins.path {
        path = ../.;
        name = "nixos-config";
      };
      diskoInstall = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko-install;
      strixInstall = pkgs.writeShellScriptBin "strix-install" ''
        set -euo pipefail

        usage() {
          cat >&2 <<'EOF'
Usage:
  strix-install --host strix-3 [--disk /dev/nvme0n1] --yes
  strix-install strix-4 --yes

Options:
  --host HOST       Target host to install: strix-3 or strix-4
  --disk DEVICE    Internal disk to wipe and install to (default: /dev/nvme0n1)
  --dry-run        Build and print the disko/install actions without formatting
  --no-efi-entry   Do not write an EFI NVRAM boot entry
  --yes, -y        Required for destructive installs

Environment:
  STRIX_FLAKE         Flake URI/path to install from (default: /etc/nixos-config)
  STRIX_HOST_KEY_DIR  Directory containing ssh_host_* keys to seed into /etc/ssh
EOF
        }

        die() {
          echo "error: $*" >&2
          exit 1
        }

        prepare_default_flake() {
          local original="$1"
          if [[ "$original" != "/etc/nixos-config" ]]; then
            printf '%s\n' "$original"
            return
          fi

          local staged="/tmp/nixos-config-install"
          local stub_root="/tmp/strix-install-stubs"
          echo "staging installer flake from $original to $staged" >&2
          rm -rf "$staged" "$stub_root"
          mkdir -p "$staged" "$stub_root/hellas" "$stub_root/nanokvm"
          cp -aL "$original"/. "$staged"/

          cat > "$stub_root/hellas/flake.nix" <<'EOF'
{
  description = "temporary hellas stub for strix install";
  outputs = { self }: {
    packages = {
      x86_64-linux = { };
      aarch64-linux = { };
      riscv64-linux = { };
    };
    overlays.default = final: prev: { };
    nixosModules.default = { ... }: { };
    homeManagerModules.default = { ... }: { };
  };
}
EOF

          cat > "$stub_root/nanokvm/flake.nix" <<'EOF'
{
  description = "temporary nanokvm stub for strix install";
  outputs = { self }: {
    packages = {
      x86_64-linux = { };
      aarch64-linux = { };
      riscv64-linux = { };
    };
    overlays.default = final: prev: { };
    nixosModules.nanokvm = { ... }: { };
    nixosModules.boards.pcie.mainline.sd = { ... }: { };
  };
}
EOF

          ${pkgs.gnused}/bin/sed -i \
            -e 's|url = "git+file:///mnt/Home/src/node?shallow=1";|url = "path:/tmp/strix-install-stubs/hellas";|' \
            -e 's|url = "path:/mnt/Home/src/nixos-nanokvm";|url = "path:/tmp/strix-install-stubs/nanokvm";|' \
            "$staged/flake.nix"

          (
            cd "$staged"
            ${pkgs.nix}/bin/nix flake lock \
              --override-input hellas "path:$stub_root/hellas" \
              --override-input nanokvm "path:$stub_root/nanokvm" \
              >/dev/null
          )

          printf '%s\n' "$staged"
        }

        host=""
        disk="/dev/nvme0n1"
        dry_run=0
        yes=0
        write_efi=1

        while [[ $# -gt 0 ]]; do
          case "$1" in
            strix-3|strix-4)
              [[ -z "$host" ]] || die "host specified more than once"
              host="$1"
              shift
              ;;
            --host)
              [[ $# -ge 2 ]] || die "--host requires an argument"
              host="$2"
              shift 2
              ;;
            --disk)
              [[ $# -ge 2 ]] || die "--disk requires an argument"
              disk="$2"
              shift 2
              ;;
            --dry-run)
              dry_run=1
              shift
              ;;
            --no-efi-entry)
              write_efi=0
              shift
              ;;
            --yes|-y)
              yes=1
              shift
              ;;
            -h|--help)
              usage
              exit 0
              ;;
            *)
              die "unknown argument: $1"
              ;;
          esac
        done

        case "$host" in
          strix-3|strix-4) ;;
          "") usage; die "missing --host" ;;
          *) die "unsupported host: $host" ;;
        esac

        if [[ "$dry_run" != 1 && "$yes" != 1 ]]; then
          die "refusing to wipe $disk without --yes"
        fi

        if [[ "$dry_run" != 1 && ! -b "$disk" ]]; then
          die "$disk is not a block device"
        fi

        flake="''${STRIX_FLAKE:-/etc/nixos-config}"
        if [[ "$flake" == *#* ]]; then
          die "STRIX_FLAKE should be the base flake URI/path, without #host"
        fi
        if [[ "$flake" != *:* && ! -e "$flake/flake.nix" ]]; then
          die "flake path $flake does not contain flake.nix"
        fi
        flake="$(prepare_default_flake "$flake")"

        host_key_dir="''${STRIX_HOST_KEY_DIR:-/var/lib/strix-installer/host-keys/$host}"
        generated_keys=0
        if [[ "$dry_run" != 1 ]]; then
          if [[ ! -e "$host_key_dir/ssh_host_ed25519_key" && ! -e "$host_key_dir/ssh_host_rsa_key" ]]; then
            install -d -m 0755 "$host_key_dir"
            ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "root@$host" -f "$host_key_dir/ssh_host_ed25519_key"
            ${pkgs.openssh}/bin/ssh-keygen -q -t rsa -b 4096 -N "" -C "root@$host" -f "$host_key_dir/ssh_host_rsa_key"
            generated_keys=1
          fi

          [[ -s "$host_key_dir/ssh_host_ed25519_key" ]] || die "missing $host_key_dir/ssh_host_ed25519_key"
          [[ -s "$host_key_dir/ssh_host_ed25519_key.pub" ]] || die "missing $host_key_dir/ssh_host_ed25519_key.pub"
          [[ -s "$host_key_dir/ssh_host_rsa_key" ]] || die "missing $host_key_dir/ssh_host_rsa_key"
          [[ -s "$host_key_dir/ssh_host_rsa_key.pub" ]] || die "missing $host_key_dir/ssh_host_rsa_key.pub"
          chmod 0600 "$host_key_dir"/ssh_host_*_key
          chmod 0644 "$host_key_dir"/ssh_host_*_key.pub

          age_recipient="$(${pkgs.ssh-to-age}/bin/ssh-to-age -i "$host_key_dir/ssh_host_ed25519_key.pub")"
          if [[ "$generated_keys" == 1 ]]; then
            echo "generated SSH host keys in $host_key_dir" >&2
          else
            echo "reusing SSH host keys from $host_key_dir" >&2
          fi
          echo "$host SOPS age recipient: $age_recipient" >&2
        fi

        cmd=(
          ${diskoInstall}/bin/disko-install
          --mode format
          --flake "$flake#$host"
          --disk disk1 "$disk"
          --extra-files "$host_key_dir" /etc/ssh
          --show-trace
        )

        if [[ "$write_efi" == 1 ]]; then
          cmd+=(--write-efi-boot-entries)
        fi
        if [[ "$dry_run" == 1 ]]; then
          cmd+=(--dry-run)
        fi

        printf 'running:' >&2
        printf ' %q' "''${cmd[@]}" >&2
        printf '\n' >&2

        "''${cmd[@]}"
      '';
    in
    {
      imports = [
        (inputs.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix")
        ../profiles/fleet-core.nix
      ];

      system.stateVersion = "25.05";
      sconfig.profile = "server";

      networking = {
        hostName = "strix-installer";
        firewall.enable = false;
      };

      isoImage.volumeID = "STRIXINSTALL";

      services.getty.autologinUser = lib.mkForce "grw";
      services.openssh.settings.PermitRootLogin = "prohibit-password";
      users.users.root.openssh.authorizedKeys.keys =
        config.users.users.grw.openssh.authorizedKeys.keys;

      environment = {
        etc."nixos-config".source = repoSource;
        systemPackages = with pkgs; [
          strixInstall
          diskoInstall
          gitMinimal
          jq
          nvme-cli
          parted
          pciutils
          sops
          ssh-to-age
          tmux
          usbutils
          vim
        ];
      };

      programs.command-not-found.enable = false;
    };
in
{
  router = sys "x86_64-linux" ./x86/router;
  router-usb = sys "x86_64-linux" ./x86/router;
  n100 = sys "x86_64-linux" ./x86/n100;

  # NVIDIA GPU machine
  fuckup = sysCuda "x86_64-linux" ./x86/fuckup;

  # AMD GPU machines. trex uses Vulkan/RADV and stays on the base package set;
  # the Strix machines use the ROCm package set for gfx1151 work.
  trex = sys "x86_64-linux" ./x86/trex;
  strix-1 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 1);
  # Keep both Strix machines on the same generic ROCm package set for
  # reliability work. The znver5 package set is useful for performance A/B
  # runs, but it makes routine system rebuilds depend on gccarch-specific
  # builders.
  strix-2 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 2);
  strix-3 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 3);
  strix-4 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 4);

  rock-5b = sys "aarch64-linux" ./aarch64/rock5b;
  prime = sys "aarch64-linux" ./aarch64/prime;
  neo2 = sys "aarch64-linux" ./aarch64/nanopi-neo2;
  bluefield2 = sys "aarch64-linux" ./aarch64/bluefield2;

  # Cross-compiled aarch64 (built on x86_64)
  rock-5b-cross = sysCross ./aarch64/rock5b;
  prime-cross = sysCross ./aarch64/prime;
  neo2-cross = sysCross ./aarch64/nanopi-neo2;
  bluefield2-cross = sysCross ./aarch64/bluefield2;
  bluefield2-rescue = sysCross ./aarch64/bluefield2/rescue.nix;

  # RISC-V (cross-built on x86_64)
  nanokvm = sysRiscvNanokvm ./riscv/nanokvm;
  k3 = sysRiscvK3 ./riscv/k3;
  k3Installer = sysRiscvK3 ./riscv/k3/kexec-installer.nix;
  k3InitrdRescue = sysRiscvK3 ./riscv/k3/initrd-rescue.nix;
  k3SdImage = sysRiscvK3 ./riscv/k3/sd-image.nix;

  strix-installer = sys "x86_64-linux" strixInstaller;
}
