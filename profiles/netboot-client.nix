{ config, lib, pkgs, network, ... }:
let
  hostName = config.networking.hostName;
  self = network.hosts.${hostName};
  trexIp = network.primaryIp network.hosts.trex;
  clientIp = network.primaryIp self;

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

  # Shared model cache replacing the local-NVMe /models. Not boot-critical.
  # Mounted directly at boot rather than via x-systemd.automount: the nix
  # builders list /models in extra-sandbox-paths, and bind-mounting an
  # un-triggered autofs mountpoint into a sandbox userns fails with EPERM,
  # which aborts every build scheduled to the host (not just model builds).
  fileSystems."/models" = {
    device = "${trexIp}:/strix-models";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "ro"
      "nofail"
      "_netdev"
      "rsize=1048576"
      "wsize=1048576"
      "nconnect=8"
    ];
  };

  boot.supportedFilesystems = [ "nfs" ];
  boot.initrd.supportedFilesystems = [ "nfs" "overlay" ];
  boot.initrd.availableKernelModules = [
    "r8169"
    "nfsv4"
    "overlay"
    # Keep the diskless image bootable under KVM for regression tests.
    "virtio_pci"
    "virtio_net"
  ];
  boot.initrd.kernelModules = [ "nfsv4" ];

  # Static stage-1 networking (systemd initrd) mirroring the stage-2
  # 10-lan config. systemd-networkd-wait-online gates the NFS mounts via
  # network-online.target, and the address survives the initrd -> stage 2
  # transition (no flush; stage 2 sets KeepConfiguration on eno1).
  boot.initrd.systemd.network = {
    enable = true;
    links."00-netboot-eno1" = {
      matchConfig.MACAddress = self.mac;
      linkConfig.Name = "eno1";
    };
    networks."10-lan" = {
      matchConfig.Name = "eno1";
      address = [ "${clientIp}/${toString network.vlans.lan.cidr}" ];
      gateway = [ network.routerIp ];
      networkConfig.DHCP = "no";
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # Restore the sealed identity before sshd's key generation and before
  # sops-nix installs secrets. Boot-time activation runs ahead of all units,
  # so this wins both races naturally; the explicit setupSecrets dep also
  # covers `switch` reordering. If the TPM refuses the blob (cleared fTPM),
  # this snippet fails loudly in the activation log and the host simply
  # boots with the disposable-identity behaviour below.
  system.activationScripts = lib.mkIf hasHostKeyCredential {
    restoreHostIdentity = lib.stringAfter [ "specialfs" ] ''
      umask 077
      mkdir -p /etc/ssh
      ${config.systemd.package}/bin/systemd-creds decrypt --name=ssh_host_ed25519_key \
        ${hostKeyCredential} /etc/ssh/ssh_host_ed25519_key
    '';
    # Merges into sops-nix's script; assumes the host declares sops secrets
    # (a deps-only definition would fail eval otherwise).
    setupSecrets.deps = [ "restoreHostIdentity" ];
  };

  environment.systemPackages = [ strixNetbootEnroll ];

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
