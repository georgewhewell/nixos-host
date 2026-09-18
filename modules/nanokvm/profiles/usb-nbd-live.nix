{ nanokvm }:
# USB-recovery NBD-live profile. Pivots out of the kernel-test initrd
# into a full NixOS stage 2 whose root lives on `/dev/nbd0`, served by
# the host runner over USB-ECM by default. The closure on disk is
# erofs-compressed and read-only; writes go to tmpfs overlays.
#
# This is the workhorse profile for day-to-day iteration on the dev
# board — `nix run .#boards.licheerv.<kernel>.live.usb` reboots the
# device, kexecs into this stage 2, and lands you at an SSH login on
# 10.55.0.1.
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
    ../modules/usb-nbd-live.nix
  ];

  networking = {
    hostName = lib.mkDefault "nanokvm-nbd-live";
    useDHCP = lib.mkForce false;
    useNetworkd = true;
    firewall.enable = lib.mkForce false;
  };

  system.nixos-init.enable = true;
  system.etc.overlay.enable = true;
  services.userborn.enable = true;

  sg2002 = {
    authorizedKeys = rootAuthorizedKeys;
    usbGadget.network.enable = true;
  };

  # Stage-2 parallel service startup peaks memory at ~75% of the
  # cv1800's 216 MB. Without swap the kernel goes deep into reclaim,
  # systemd's mainloop stalls past RuntimeWatchdogSec=30s, and dw_wdt
  # resets the chip. 50% memoryPercent ≈ 108 MB of zstd-compressed
  # swap — roughly doubles effective RAM through the fork-storm
  # window. (sg2002.tuning.enable also sets this but pulls in
  # noatime/journald-volatile side effects we keep orthogonal.)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };
  systemd.services.sshd = lib.mkIf config.services.userborn.enable {
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
  };

  services.nanokvm = {
    enable = true;
    openFirewall = true;
    # USB gadget is set up by the initrd already; don't duplicate.
    usbGadget.enable = false;
  };

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

  # Interactive diagnostics: btop for a richer TUI, iperf3 for throughput,
  # fio for NBD read tests.
  environment.systemPackages = with pkgs; [
    btop
    fio
    iperf3
    procps
  ];
}
