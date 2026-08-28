# Sipeed LicheeRV-Nano-W (SG2002 / RISC-V C906) — USB-booted, NFS-rooted
# camera node hanging directly off trex's USB port.
#
# Unlike nanokvm (SD card + extlinux), this board has no local boot
# medium in play: each boot is pushed over USB (rom-dl FIP + fastboot
# FIT from trex), the initrd brings up the private USB link and mounts
# /nix/store from trex at 10.55.0.2, and stage 2 runs from that. The
# camera DTB wires the GC4653, I2C4, MCLK, reset, CSI receiver and DMA
# pool; the next automatic USB boot picks up the fleet closure through
# the runner's init= bootarg.
#
# Hardware/boot stack (kernel, DTB, initrd, NFS live root) comes from
# the nanokvm flake as a module, like nanokvm — see `sysRiscvLicheerv`
# in ../../default.nix. Same dietary constraints: 256 MB.
{
  inputs,
  lib,
  network,
  ...
}:
{
  # Colmena reconstructs nodes through eval-config.nix and therefore does not
  # inherit the nested nixpkgs flake's source metadata automatically. Pin it
  # explicitly so the standalone and hive evaluations are byte-identical.
  system.nixos.revision = lib.mkForce inputs.nanokvm.inputs.nixpkgs.rev;
  system.nixos.versionSuffix = lib.mkForce ".${
    builtins.substring 0 8 inputs.nanokvm.inputs.nixpkgs.lastModifiedDate
  }.${inputs.nanokvm.inputs.nixpkgs.shortRev}";

  imports = [
    # Fleet identity: grw + sudo, ssh, zsh, /etc/hosts, locale.
    ../../../profiles/fleet-core.nix
    # Keep the 256 MB target out of the normal workstation/server default set.
    ../../../profiles/headless.nix
    ../../../profiles/watchdog.nix
  ];

  sconfig.profile = "server";

  networking.hostName = "licheerv";

  # WiFi stays off: this unit's AIC8800 ships the same burned-in default
  # MAC as nanokvm's (38:7a:cc:40:41:e3), so both on the wifi VLAN would
  # collide. The NFS root uses the private USB gadget link.
  sg2002.wifi.enable = lib.mkForce false;

  # Fleet hosts are key-only (fleet-core). The live profile's first-boot
  # password path stays as a local recovery fallback only.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;

  # This is not a KVM: no nanokvm server, no HDMI pipeline. The GC4653
  # camera work runs ad-hoc until it earns a service here.
  services.nanokvm.enable = lib.mkForce false;

  # Lingering starts a per-user systemd manager at boot whether or not
  # grw ever logs in — not worth the RAM here.
  users.users.grw.linger = lib.mkForce false;

  # Same 256 MB memory discipline as nanokvm, minus zram: the live
  # profile disables it on purpose (zram0 is created before the stage-2
  # udev coldplug and the lost-event device unit costs 90 s of boot).
  nix = {
    gc.automatic = lib.mkForce false;
    optimise.automatic = lib.mkForce false;
    registry = lib.mkForce {};
    settings.auto-optimise-store = lib.mkForce false;
  };
  services = {
    logrotate.enable = lib.mkForce false;
    fstrim.enable = lib.mkForce false;
    earlyoom.enable = false;
  };
  security.pam.services.sshd.startSession = lib.mkForce false;
  systemd.services = {
    sshd.serviceConfig.OOMScoreAdjust = lib.mkForce (-1000);
    systemd-networkd.serviceConfig.OOMScoreAdjust = lib.mkForce (-900);
  };
  # The live root is tmpfs + NFS store: keep the journal in RAM, capped.
  services.journald.extraConfig = ''
    Storage=volatile
    MaxLevelStore=warning
    RuntimeMaxUse=16M
    RuntimeMaxFileSize=4M
    RateLimitIntervalSec=30s
    RateLimitBurst=100
  '';
  systemd.coredump.enable = lib.mkForce false;

  # Keep a deterministic address on the optional RJ45 even though the
  # live store rides USB. The SG2002 GMAC has no fused address and would
  # otherwise roll a random one every boot. Locally administered: 02,
  # "LRV", .29.
  systemd.network.networks."20-eth0".linkConfig.MACAddress =
    network.hosts.licheerv.mac;

  # Same bring-up-softened watchdog policy as nanokvm (hardware WDT TOP
  # is ~85 s; relax the software panic paths until the board is stable).
  boot.kernelParams = lib.mkAfter [
    "panic=10"
    "panic_on_oops=0"
    "softlockup_panic=0"
    "hung_task_panic=0"
    "workqueue.panic_on_stall=0"
    "workqueue.watchdog_thresh=360"
    "rcupdate.rcu_cpu_stall_timeout=360"
  ];
  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkForce 10;
    "kernel.panic_on_oops" = lib.mkForce 0;
    "kernel.softlockup_panic" = lib.mkForce 0;
    "kernel.hung_task_panic" = lib.mkForce 0;
    "kernel.hardlockup_panic" = lib.mkForce 0;
    "kernel.panic_on_rcu_stall" = lib.mkForce 0;
    "kernel.max_rcu_stall_to_panic" = lib.mkForce 0;
    "kernel.hung_task_timeout_secs" = lib.mkForce 600;
    "kernel.watchdog_thresh" = lib.mkForce 60;
  };
  # The board's usb-control module owns the watchdog policy for live
  # boots (sg2002-watchdog-keeper.nix forces RuntimeWatchdogSec off — a
  # live NFS box that stalls on the network must not watchdog-loop).

  # Cross-compiled on the x86_64 builder; the closure lands in the
  # trex's /nix/store, which the board already mounts over NFS — activation
  # copies nothing to the 256 MB target. Only trex can reach the private
  # gadget address.
  deployment = {
    targetHost = lib.mkDefault "10.55.0.1";
    targetUser = "grw";
    buildOnTarget = false;
  };
}
