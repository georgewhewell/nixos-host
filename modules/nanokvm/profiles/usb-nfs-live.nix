{ nanokvm }:
# USB-recovery NFS-live profile. Boots the kernel+initrd uploaded over
# USB into a full NixOS stage 2 whose /nix/store is an NFSv4 export
# from the host runner (see modules/usb-nfs-live.nix) — the successor
# of usb-nbd-live.nix for day-to-day iteration, with no rootfs image
# to rebuild between generations.
#
# `nix run .#boards.picoclaw.mainline.live.usb.usb-boot` reboots the
# device, boots this system, and lands you at an SSH login on
# 10.55.0.1; detaching the debug shell kexecs the next generation.
{ config
, lib
, pkgs
, modulesPath
, rootAuthorizedKeys ? [ ]
, ...
}: {
  imports = [
    # `modulesPath` (not the nixpkgs flake input): it resolves at
    # imports-time without needing specialArgs, which keeps the whole
    # board module list re-instantiable from `_module.args.modules`.
    "${modulesPath}/profiles/image-based-appliance.nix"
    (nanokvm + "/modules/sg2002-usb-gadget-initrd.nix")
    ../modules/usb-nfs-live.nix
  ];

  networking = {
    hostName = lib.mkDefault "nanokvm-nfs-live";
    useDHCP = lib.mkForce false;
    useNetworkd = true;
    firewall.enable = lib.mkForce false;
  };

  system.nixos-init.enable = true;
  system.etc.overlay.enable = true;
  services.userborn = {
    enable = true;
    # This profile is a throw-away appliance image with switching disabled.
    # Generate passwd/group/shadow at build time instead of making the board
    # fetch and run userborn over full-speed USB NFS during every boot.
    static = true;
  };

  sg2002 = {
    authorizedKeys = rootAuthorizedKeys;
    usbGadget.network.enable = true;
  };

  # zram0 is created before the stage-2 udev coldplug, so its generated
  # .device unit never observes the event and delays boot by 90 seconds.
  # Keep it off for the small bring-up closure; the large kexec staging copy
  # that originally motivated swap is disabled below as well.
  zramSwap.enable = false;

  # Both consoles remain kernel log sinks. Avoid generator-created serial
  # gettys whose .device units have the same lost-udev-event problem.
  boot.kernelParams = [
    "systemd.getty_auto=no"
    # Ten parallel workers consumed roughly 62 MiB during the failed boot.
    # This one-core, 256-MiB target needs a deliberately small hotplug burst.
    "udev.children_max=2"
  ];

  services.openssh = {
    enable = true;
    # RSA-4096 generation took tens of seconds and was repeatedly killed
    # under memory pressure. Ed25519 is sufficient for this ephemeral target.
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };
  systemd.services.sshd = lib.mkIf (config.services.userborn.enable && !config.services.userborn.static) {
    after = [
      "systemd-tmpfiles-setup.service"
      "userborn.service"
    ];
    wants = [
      "systemd-tmpfiles-setup.service"
      "userborn.service"
    ];
  };

  users.users = {
    root = {
      initialPassword = "nixos";
      openssh.authorizedKeys.keys = rootAuthorizedKeys;
    };
    nixos = {
      isNormalUser = true;
      initialPassword = "nixos";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = rootAuthorizedKeys;
    };
  };

  nanokvm.usbControl = {
    stage2ShellUser = "nixos";
    # prepare-kexec-stage copies a ~21 MiB EROFS image into /run while its
    # NFS source remains cached. That ~44 MiB transient peak consumed the
    # atomic reserve DWC2 needs for RX on this 256 MiB board.
    kexec.enable = false;
  };

  # Keep the fleet's normal DNS and clock services. These targets have no
  # usable RTC, so disabling resolved/timesyncd leaves every cold boot at the
  # firmware timestamp even after the network is online.
  systemd.oomd.enable = false;
  systemd.network.wait-online.enable = false;

  # Unlike the NBD live profile, nanokvm-server stays off here: the
  # PicoClaw work starts from a minimal base, and the server's
  # HDMI/camera expectations don't apply to this board.
  services.nanokvm.enable = lib.mkDefault false;

  # The vendor 5.10 SG2002 config lacks the
  # CONFIG_ARCH_MMAP_RND_*_MAX symbols nixpkgs' generic sysctl module
  # expects when generating this file.
  environment.etc."sysctl.d/55-nixos-aslr-entropy.conf".source = lib.mkForce (
    pkgs.writeText "empty-aslr-entropy.conf" ""
  );

  environment.defaultPackages = lib.mkForce [ ];
  documentation.enable = lib.mkForce false;
  programs.nano.enable = lib.mkForce false;
  programs.less.enable = lib.mkForce false;

  # Interactive diagnostics: btop for a richer TUI, iperf3 for USB/NFS
  # throughput checks.
  environment.systemPackages = with pkgs; [
    btop
    iperf3
    procps
  ];
}
