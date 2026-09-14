{ config, lib, pkgs, network, ... }:
let
  hostName = config.networking.hostName;
  self = network.hosts.${hostName};
  trexIp = network.primaryIp network.hosts.trex;
  clientIp = network.primaryIp self;
  # Firmware now boots from a cabled ConnectX-5 port rather than the onboard
  # Realtek NIC. Record that identity explicitly so the same interface keeps
  # the LAN address when Linux replaces iPXE.
  bootMac = self.netbootMac or self.mac;
  bootLinuxMac = self.netbootLinuxMac or bootMac;
  bootMacMatch = lib.concatStringsSep " " (lib.unique [ bootMac bootLinuxMac ]);
  bootMacCandidates =
    lib.unique ([ bootMac bootLinuxMac ] ++ (self.extraMacs or [ ]));
  bootMacCandidateArgs = lib.escapeShellArgs bootMacCandidates;
  sharesFabric = self.netbootSharesFabric or false;
  firmwareSnapshotDir = "/var/lib/bios-setup-var/snapshots";

  # Kernel-direct NFSv4.2 mount options. The initrd has no mount.nfs
  # helper, so every option here must be understood by the kernel nfs4
  # filesystem itself; addr= is mandatory because the helper normally
  # injects it.
  nfsBootOptions = [
    "vers=4.2"
    "addr=${trexIp}"
    # mount.nfs normally derives this from the selected route. The initrd
    # performs a kernel-direct mount, so supply it explicitly; without it
    # NFSv4 fails while walking the exported pseudo-root.
    "clientaddr=${clientIp}"
    "hard"
    "nconnect=8"
    "rsize=1048576"
    "wsize=1048576"
  ];

  # TPM-sealed persistent identity. The root is tmpfs, so without this every
  # boot mints a fresh ssh host key — churning known_hosts and orphaning
  # sops-nix, whose age identity derives from the ed25519 host key. Running
  # `strix-netboot-enroll` once on a host seals its canonical key to that
  # machine's TPM; the blob ships in the world-readable store, which is fine
  # because only that TPM can unseal it (device-bound, no PCR policy — a
  # BIOS fTPM reset just means enrolling again). Hosts without a blob keep
  # the fresh-keys-per-boot behaviour.
  hostKeyCredential = ./netboot-host-keys + "/${hostName}.cred";
  hasHostKeyCredential = builtins.pathExists hostKeyCredential;

  strixNetbootEnroll = pkgs.writeShellScriptBin "strix-netboot-enroll" ''
    set -euo pipefail

    key="''${1:-/etc/ssh/ssh_host_ed25519_key}"
    out="/tmp/${hostName}.cred"

    # --name must match the decrypt side exactly: systemd-creds otherwise
    # validates against the blob's basename, which in the store is hashed.
    # Explicit tpm2/no-PCR flags keep the blob device-bound regardless of
    # the running systemd's defaults (auto would mix in the tmpfs host key;
    # PCR binding dies on every firmware update).
    systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs="" \
      --name=ssh_host_ed25519_key "$key" "$out"

    echo "sealed $key -> $out; commit it as profiles/netboot-host-keys/${hostName}.cred"
    echo "age recipient for .sops.yaml (run sops updatekeys if this identity is new):"
    ${pkgs.openssh}/bin/ssh-keygen -y -f "$key" | ${pkgs.ssh-to-age}/bin/ssh-to-age
  '';
in
{
  # Diskless netboot client: kernel+initrd arrive via iPXE/HTTP, the Nix
  # store is a read-only NFS export from trex with a tmpfs overlay for
  # writes (benchmark builds and interactive shells). Everything else is
  # stateless tmpfs; Home Manager recreates grw's home on every boot.

  # No local bootloader: the boot chain is firmware PXE -> iPXE -> HTTP.
  # switch-to-configuration still needs an install hook so colmena's
  # `switch` action succeeds; the real "bootloader update" is
  # `strix-netboot-update` on trex.
  boot.loader.grub.enable = false;
  boot.loader.external = {
    enable = true;
    installHook = "${pkgs.coreutils}/bin/true";
  };

  boot.tmp.useTmpfs = true;

  fileSystems."/" = {
    fsType = "tmpfs";
    # Bound all ordinary volatile state (/etc, /var, /home and build
    # temporaries) so diskless boot cannot consume the machines' UMA.
    options = [ "mode=0755" "size=2G" ];
  };

  fileSystems."/nix/.ro-store" = {
    device = "${trexIp}:/nix-store";
    fsType = "nfs4";
    # The store is immutable content-addressed data, so relax close-to-open
    # coherency and cache attributes aggressively.
    options = nfsBootOptions ++ [ "ro" "nocto" "actimeo=600" ];
    neededForBoot = true;
  };

  fileSystems."/nix/.rw-store" = {
    fsType = "tmpfs";
    # Together with the 2 GiB root tmpfs above, netboot-specific writable
    # storage has a hard aggregate ceiling of 4 GiB.
    options = [ "mode=0755" "size=2G" ];
    neededForBoot = true;
  };

  fileSystems."/nix/store" = {
    overlay = {
      lowerdir = [ "/nix/.ro-store" ];
      upperdir = "/nix/.rw-store/store";
      workdir = "/nix/.rw-store/work";
    };
    neededForBoot = true;
  };

  # `/` is tmpfs. Mount this host's private trex export so a snapshot taken at
  # every boot remains available after the cluster is shut down. The export is
  # restricted to this inventory address on the server.
  fileSystems.${firmwareSnapshotDir} = {
    device = "${trexIp}:/strix-firmware-snapshots/${hostName}";
    fsType = "nfs4";
    options = nfsBootOptions ++ [
      "rw"
      "sync"
      "nofail"
      "_netdev"
      "x-systemd.mount-timeout=15s"
      "noexec"
      "nosuid"
      "nodev"
    ];
  };

  systemd.services.bios-setup-var-snapshot = {
    description = "Snapshot all EFI variables to trex";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig = {
      ConditionPathIsDirectory = "/sys/firmware/efi/efivars";
      RequiresMountsFor = [ firmwareSnapshotDir ];
    };
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      set -eu
      IFS= read -r boot_id < /proc/sys/kernel/random/boot_id
      captured_at="$(${pkgs.coreutils}/bin/date --utc +%Y%m%dT%H%M%SZ)"
      exec ${pkgs.bios-setup-var}/bin/bios-setup-var \
        --db ${pkgs.bios-setup-var}/share/bios-setup-var/faex9-1.04-known.json \
        snapshot \
        "${firmwareSnapshotDir}/$captured_at-$boot_id"
    '';
  };

  boot.supportedFilesystems = [ "nfs" ];
  boot.initrd.supportedFilesystems = [ "nfs" "overlay" ];
  boot.initrd.availableKernelModules = [
    "r8169"
    "mlx5_core"
    "nfsv4"
    "overlay"
    # Keep the diskless image bootable under KVM for regression tests.
    "virtio_pci"
    "virtio_net"
  ];
  # mlx5_core is both available and explicitly loaded. SharedIO firmware can
  # leave the PCI function without a fresh uevent when Linux takes over from
  # iPXE, so relying only on modalias autoloading is not robust enough here.
  boot.initrd.kernelModules = [ "mlx5_core" "nfsv4" ];

  # The rescue unit embeds an absolute `ip` path. Initrd systemd units retain
  # their script, but not arbitrary store references made by that script.
  boot.initrd.systemd.storePaths = [ "${pkgs.iproute2}/bin/ip" ];

  # Do not leave the NFS-root interface to udev timing alone. UEFI SharedIO
  # PXE can hand mlx5_core a PF under a different MAC from the one advertised
  # by DHCP, and on some boots the corresponding .link event has already
  # passed before initrd-networkd starts. Resolve the cabled PF from every
  # inventory identity, bind any still-unbound Mellanox Ethernet function,
  # and establish the static route before networkd and the NFS mounts run.
  boot.initrd.systemd.services.strix-netboot-link-rescue = {
    description = "Establish the Strix MLX5 NFS-root link";
    wantedBy = [ "initrd.target" ];
    before = [
      "systemd-networkd.service"
      "systemd-networkd-wait-online.service"
      "remote-fs-pre.target"
    ];
    after = [
      "systemd-modules-load.service"
      "systemd-udev-trigger.service"
    ];
    wants = [
      "systemd-modules-load.service"
      "systemd-udev-trigger.service"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.kmod}/bin/modprobe mlx5_core
      ${config.systemd.package}/bin/udevadm settle --timeout=30 || true

      boot_if=
      for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
        # Prefer the exact PXE/Linux identities in inventory order. All four
        # hosts may expose sibling SharedIO PFs, so "first mlx5 device" is not
        # a safe selector.
        for wanted in ${bootMacCandidateArgs}; do
          for candidate in /sys/class/net/*; do
            [ -r "$candidate/address" ] || continue
            [ "$(${pkgs.coreutils}/bin/cat "$candidate/address")" = "$wanted" ] || continue
            boot_if="''${candidate##*/}"
            break 2
          done
        done

        [ -n "$boot_if" ] && break

        # Retry functions for which the firmware-to-kernel handoff left no
        # driver. Already-bound functions are never reset here.
        for device in /sys/bus/pci/devices/*; do
          [ "$(${pkgs.coreutils}/bin/cat "$device/vendor" 2>/dev/null)" = "0x15b3" ] || continue
          case "$(${pkgs.coreutils}/bin/cat "$device/class" 2>/dev/null)" in
            0x0200*) ;;
            *) continue ;;
          esac
          [ -e "$device/driver" ] && continue
          bdf="''${device##*/}"
          echo "$bdf" > /sys/bus/pci/drivers/mlx5_core/bind 2>/dev/null || true
        done

        ${config.systemd.package}/bin/udevadm settle --timeout=2 || true
        ${pkgs.coreutils}/bin/sleep 1
      done

      if [ -z "$boot_if" ]; then
        echo "no MLX5 netdev matched: ${lib.concatStringsSep ", " bootMacCandidates}" >&2
        exit 1
      fi

      if [ "$boot_if" != eno1 ]; then
        ${pkgs.iproute2}/bin/ip link set dev "$boot_if" down
        ${pkgs.iproute2}/bin/ip link set dev "$boot_if" name eno1
      fi

      ${pkgs.iproute2}/bin/ip link set dev eno1 up
      ${pkgs.iproute2}/bin/ip address replace \
        ${clientIp}/${toString network.vlans.lan.cidr} dev eno1
      ${lib.optionalString sharesFabric ''
        ${pkgs.iproute2}/bin/ip address replace \
          ${network.cidrOf "fabric" self.addresses.fabric} dev eno1
      ''}
      ${pkgs.iproute2}/bin/ip route replace default via ${network.routerIp} dev eno1
      echo "NFS-root link ready on eno1 ($(${pkgs.coreutils}/bin/cat /sys/class/net/eno1/address))"
    '';
  };

  # Static stage-1 networking (systemd initrd) mirroring the stage-2
  # 10-lan config. systemd-networkd-wait-online gates the NFS mounts via
  # network-online.target, and the address survives the initrd -> stage 2
  # transition (no flush; stage 2 sets KeepConfiguration on eno1).
  boot.initrd.systemd.network = {
    enable = true;
    links."00-netboot-eno1" = {
      # Strix 1/2 PXE with a firmware-assigned SharedIO MAC, then mlx5_core
      # restores the PF's permanent Linux MAC. systemd accepts a whitespace-
      # separated OR-list here, so either identity names the one cabled rail.
      matchConfig.MACAddress = bootMacMatch;
      linkConfig.Name = "eno1";
    };
    networks."10-lan" = {
      matchConfig.Name = "eno1";
      address = [
        "${clientIp}/${toString network.vlans.lan.cidr}"
      ] ++ lib.optionals sharesFabric [
        (network.cidrOf "fabric" self.addresses.fabric)
      ];
      gateway = [ network.routerIp ];
      networkConfig = {
        DHCP = "no";
        # The Nix store is already live over NFS when initrd-networkd stops.
        # Preserve the static address across switch-root; otherwise removing
        # it deadlocks stage 2 before its own networkd can restore the link.
        KeepConfiguration = "static";
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # Restore the sealed identity before sshd's key generation and before
  # sops-nix installs secrets. Boot-time activation runs ahead of all units,
  # so this wins both races naturally; the explicit setupSecrets dep also
  # covers `switch` reordering. If the TPM refuses the blob (cleared fTPM),
  # this snippet fails loudly in the activation log and the host simply
  # boots with the disposable-identity behaviour below.
  # The subshell keeps the umask from leaking into later activation snippets:
  # they all run in one shell, and this snippet sorts before `usrbinenv`,
  # whose `mkdir -p /usr/bin` would then create /usr as 0700 on every boot
  # (the root here is tmpfs, so /usr never pre-exists) — breaking every
  # `#!/usr/bin/env` shebang for non-root users.
  system.activationScripts = lib.mkIf hasHostKeyCredential {
    restoreHostIdentity = lib.stringAfter [ "specialfs" ] ''
      (
        umask 077
        mkdir -p /etc/ssh
        ${config.systemd.package}/bin/systemd-creds decrypt --name=ssh_host_ed25519_key \
          ${hostKeyCredential} /etc/ssh/ssh_host_ed25519_key
      )
    '';
    # Merges into sops-nix's script; assumes the host declares sops secrets
    # (a deps-only definition would fail eval otherwise).
    setupSecrets.deps = [ "restoreHostIdentity" ];
  };

  environment.systemPackages = [ strixNetbootEnroll ];

  # Belt and braces for the umask hazard above: /usr is recreated in tmpfs on
  # every boot, so enforce sane modes even if some future activation snippet
  # leaks a restrictive umask again. Non-root users need the x bit on /usr to
  # resolve /usr/bin/env shebangs (2026-08-26 incident: /usr was 0700).
  systemd.tmpfiles.rules = [
    "d /usr 0755 root root -"
    "d /usr/bin 0755 root root -"
  ];

  # Fallback identity: hosts without an enrolled credential (or with a
  # cleared TPM) generate fresh stage-2 host keys in the tmpfs root on
  # every boot. With a restored key present, generation is skipped and the
  # stable identity is used.
  services.openssh.hostKeys = lib.mkForce [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
    {
      path = "/etc/ssh/ssh_host_rsa_key";
      type = "rsa";
      bits = 4096;
    }
  ];

  # The store db lives in tmpfs and starts empty every boot. The iPXE
  # script passes nix_registration=<closureInfo>/registration (a path
  # inside the NFS store) so the booted closure can be registered before
  # nix-daemon starts. Mirrors nixpkgs' netboot register-nix-paths unit.
  systemd.services.strix-register-nix-paths = {
    description = "Register netboot Nix store paths";
    unitConfig.DefaultDependencies = false;
    wantedBy = [ "sysinit.target" ];
    before = [
      "sysinit.target"
      "shutdown.target"
      "nix-daemon.socket"
      "nix-daemon.service"
    ];
    after = [ "local-fs.target" ];
    conflicts = [ "shutdown.target" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      reg=""
      for o in $(cat /proc/cmdline); do
        case "$o" in
          nix_registration=*) reg="''${o#nix_registration=}" ;;
        esac
      done

      if [ -n "$reg" ] && [ -e "$reg" ]; then
        ${lib.getExe' config.nix.package "nix-store"} --load-db < "$reg"
      else
        echo "no nix_registration= on the kernel cmdline; store db left empty" >&2
      fi

      touch /etc/NIXOS
      ${lib.getExe' config.nix.package "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system
    '';
  };

  # Everything iPXE needs to boot this host, served by trex's nginx:
  #   strix-netboot-update <host> refreshes /var/lib/strix-netboot/<host>.
  # The out-link doubles as the GC root keeping the closure in trex's store.
  system.build.strixNetboot =
    let
      closure = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
      ipxeScript = pkgs.writeText "netboot-${hostName}.ipxe" ''
        #!ipxe
        kernel kernel init=${config.system.build.toplevel}/init initrd=initrd ${toString config.boot.kernelParams} nix_registration=${closure}/registration
        initrd initrd
        boot
      '';
    in
    pkgs.linkFarm "strix-netboot-${hostName}" [
      {
        name = "kernel";
        path = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
      }
      {
        name = "initrd";
        path = "${config.system.build.initialRamdisk}/initrd";
      }
      {
        name = "netboot.ipxe";
        path = ipxeScript;
      }
      {
        name = "registration";
        path = "${closure}/registration";
      }
    ];
}
