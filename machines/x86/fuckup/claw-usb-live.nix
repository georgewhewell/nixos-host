# LicheeRV-Nano "RV Claw" (PicoClaw LCD unit) host-side serving.
#
# The claw hangs off this machine's USB port and follows the same
# diskless model as trex's strix netboot clients, with USB instead of
# ethernet: whenever the board enumerates in ROM download mode (plugged
# in, or reset with no bootable medium), udev starts
# claw-usb-boot.service, which pushes FIP -> fastboot -> FIT. The FIT's
# init= is the fleet `claw` nixosConfiguration's toplevel, so plugging
# the board always boots the latest deployed claw image; the initrd
# mounts /nix/store read-only over NFSv4 from this host's gadget address
# (10.55.0.2, lib/protocol.nix in nixos-nanokvm) and stage 2 runs
# straight from this store. Referencing the runner (and through its
# bootargs the claw toplevel) from this system closure keeps both
# GC-rooted for as long as they are served — deploying fuckup refreshes
# what the next plug boots, one flake evaluation, no separate step.
{ pkgs, inputs, ... }:
let
  # The artifact builders are not a flake output of nixos-nanokvm, but
  # they are a pure function of pkgs — import them from the input's
  # source tree, exactly as its flake.nix does. pkgs here carries the
  # nanokvm overlay (allOverlays), which provides sg2002-boot-fit and
  # sg2002-usb-boot.
  nanokvmLib = inputs.nanokvm.inputs.nixpkgs.lib;
  protocol = import "${inputs.nanokvm}/lib/protocol.nix";
  hostShellPrelude = import "${inputs.nanokvm}/lib/host-prelude.nix" protocol;
  art = (import "${inputs.nanokvm}/lib/artifacts.nix" {
    lib = nanokvmLib;
    inherit hostShellPrelude;
  }) pkgs;

  clawCfg = inputs.self.nixosConfigurations.claw;

  # Same composition as the nanokvm flake's nfsLiveArtifacts for the
  # picoclaw.mainline.live.usb-lcd catalog entry, but built from the
  # fleet claw configuration so init= points at the fleet toplevel.
  clawUsbLive = art.mkNfsUsbBootRunner {
    name = "usb-boot";
    fit = art.mkBootFit {
      cfg = clawCfg;
      profile = "live";
      description = "SG2002 USB NFS live boot (claw, fleet)";
    };
    bootargs = art.mkLiveBootargs {
      cfg = clawCfg;
      # Nobody drains the ACM gadget console in this launcher flow, and
      # an undrained console=ttyGS0 backs up and wedges the kernel
      # mid-boot (why the catalog's usb-lcd-hs entry sets
      # artifactArgs.usbConsole = false). The kernel console stays on
      # ttyS0; use a picocom/ATTACH=shell manual run for console debug.
      usbConsole = false;
      # Mirror the usb-lcd catalog entry's artifactArgs.extraBootargs,
      # plus the picoclaw kernel-test's cpuidle A/B: this unit hit the
      # documented dwc2 RX stall ~12 min into its first stage 2 (usb0 RX
      # froze, the rx-guard's re-probe dropped the gadget for good and
      # the NFS root died with it). C906 WFI cpuidle is the suspect.
      extra = [
        "systemd.getty_auto=no"
        "udev.children_max=2"
        "cpuidle.off=1"
      ];
    };
    nfsServer = clawCfg.config.nanokvm.nfsLive.server;
    nfsExport = clawCfg.config.nanokvm.nfsLive.storeExport;
    waitForSsh = true;
  };
in
{
  fileSystems."/export/nix-store" = {
    device = "/nix/store";
    fsType = "none";
    options = [ "bind" ];
  };

  # The runner refuses to boot without both of these (its preflight
  # inspects exportfs output): a read-only fsid=0 pseudo-root and the
  # read-only store export, both for the point-to-point USB-link CIDR.
  services.nfs.server = {
    enable = true;
    exports = ''
      /export            10.55.0.0/24(ro,all_squash,fsid=0,no_subtree_check)
      /export/nix-store  10.55.0.0/24(ro,nohide,no_subtree_check)
    '';
  };

  # Stable path for ad-hoc runs: /var/lib/claw-usb-live/bin/usb-boot
  # (NANOKVM_ATTACH=shell for an interactive bring-up session).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/claw-usb-live - - - - ${clawUsbLive}"
  ];

  # The SG2002 ROM re-enumerates as this CVITEK download device on every
  # ~9 s USB-DL cycle, so a plugged-but-unbooted claw re-triggers the
  # rule until the service catches it; SYSTEMD_WANTS on an already-run
  # service is a no-op, so the ROM loop cannot stack instances.
  # ID_MM_DEVICE_IGNORE keeps ModemManager from probing the ROM's
  # CDC-ACM "USB Com Port" on every cycle.  Keep cdc_acm bound:
  # cv181x-rom-dl talks to the BootROM through the ttyACM device that
  # this driver creates.  Unbinding it removes the uploader's transport
  # and leaves every attempt stuck at "Connecting to ROM".
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="3346", ATTR{idProduct}=="1000", TAG+="systemd", ENV{SYSTEMD_WANTS}="claw-usb-boot.service", ENV{ID_MM_DEVICE_IGNORE}="1"
  '';

  systemd.services.claw-usb-boot = {
    description = "USB-boot the claw (LicheeRV-Nano PicoClaw) into its NFS live system";
    wantedBy = [ "multi-user.target" ];
    # udev-triggered only; starting it manually is fine too. A
    # successful pass (FIP pushed, FIT booted, SSH answered) exits 0 and
    # the board then keeps running off the kernel nfsd — nothing to
    # babysit. A give-up exits non-zero and re-arms the poller so the
    # next board reset is caught without manual intervention.
    serviceConfig = {
      Type = "simple";
      # This host's full-speed ROM path can spend ~25 seconds waiting for the
      # next enumeration and another ~45 seconds draining the multi-stage FIP
      # transfer. Ten 90-second attempts keep misses bounded without killing a
      # real upload halfway through.
      ExecStart = "${clawUsbLive}/bin/usb-boot --rom-dl-verbose --rom-dl-timeout 900 --attempts 10";
      Environment = [
        "NANOKVM_ATTACH=none"
      ];
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };
}
