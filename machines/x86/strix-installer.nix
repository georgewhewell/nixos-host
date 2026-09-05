# Strix installer ISO: live image with strix-install (disko-install wrapper)
# for provisioning the local-boot fallback on strix hosts.
{ config, pkgs, lib, inputs, ... }:
let
  repoSource = builtins.path {
    path = ../../.;
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
      mkdir -p "$staged" "$stub_root/hellas" "$stub_root/nanokvm" \
        "$stub_root/catena-runner" "$stub_root/exploratory-catena"
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
        -e 's|url = "git+file:///mnt/Home/src/nixos-nanokvm?shallow=1";|url = "path:/tmp/strix-install-stubs/nanokvm";|' \
        "$staged/flake.nix"

      (
        cd "$staged"
        ${pkgs.nix}/bin/nix flake lock \
          --override-input hellas "path:$stub_root/hellas" \
          --override-input catena-runner "path:$stub_root/catena-runner" \
          --override-input exploratory-catena "path:$stub_root/exploratory-catena" \
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
    ../../profiles/fleet-core.nix
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
}
