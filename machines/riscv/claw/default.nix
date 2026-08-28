# Sipeed LicheeRV-Nano "RV Claw" (SG2002 / RISC-V C906) — the PicoClaw
# expansion unit with the 240x240 ST7789 SPI LCD — USB-booted,
# NFS-rooted fleet member hanging off fuckup's USB port.
#
# Same diskless model as licheerv, but even the store traffic rides the
# USB gadget: each boot is pushed over USB by fuckup's usb-boot runner
# (ROM USB-DL -> FIP -> fastboot FIT), the initrd mounts /nix/store
# read-only over NFSv4 from fuckup's gadget address (10.55.0.2), and
# stage 2 runs from that. There is no LAN path at all (nowifi DTB, no
# RJ45 in play), so Colmena can only reach this node from fuckup itself
# — 10.55.0.1 is the point-to-point link partner (lib/protocol.nix in
# nixos-nanokvm).
#
# Hardware/boot stack (kernel, DTB, initrd, NFS live root, LCD
# self-test) comes from the nanokvm flake as a module, like licheerv —
# see `sysRiscvClaw` in ../../default.nix. Same dietary constraints:
# 256 MB.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  clawLcdStatus = pkgs.callPackage ../../../packages/claw-lcd-status { };
  waitForSpi = pkgs.writeShellScript "claw-lcd-wait-for-spi" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
      if [ -c /dev/spidev1.0 ]; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    echo "claw LCD SPI device did not appear: /dev/spidev1.0" >&2
    exit 1
  '';
in
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

  networking.hostName = "claw";

  # Local display: replace the board module's ST7789 self-test with the
  # fleet status dashboard — same spidev/GPIO interface, but LVGL renders
  # partial (dirty-area) frames instead of one static full-screen push.
  # The self-test holds the panel's GPIO lines exclusively, so it must
  # not run alongside.
  systemd.services.picoclaw-lcd-test.wantedBy = lib.mkForce [ ];
  systemd.services.claw-lcd-status = {
    description = "claw ST7789 LVGL status display";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = [ waitForSpi ];
      ExecStart = "${clawLcdStatus}/bin/claw-lcd-status /dev/spidev1.0 /dev/gpiochip0";
      Restart = "always";
      RestartSec = "2s";
    };
  };

  # Use the board module's full-speed LCD DTB. Both NCM and ECM on the
  # experimental high-speed DWC2 path hit a host TX watchdog after about ten
  # seconds and then failed to re-enumerate. The camera LicheeRV proves this
  # simpler full-speed ECM path through switch-root, NFS and SSH.
  sg2002.usbGadget.network.transport = lib.mkForce "ecm";
  # Prefetch stage-2 systemd's ELF dependencies while still in the initrd so
  # the switch-root transition needs less traffic from the USB-backed store.
  nanokvm.nfsLive.prefetchStage2Systemd = true;

  # Fleet hosts are key-only (fleet-core). The live profile's first-boot
  # password path stays as a local recovery fallback only.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;

  # This is not a KVM: no nanokvm server, no HDMI pipeline. The board
  # module's picoclawLcd mixin stays enabled for the DTB/spidev wiring;
  # the LVGL status service above is the panel's only userspace.
  services.nanokvm.enable = lib.mkForce false;

  # Lingering starts a per-user systemd manager at boot whether or not
  # grw ever logs in — not worth the RAM here.
  users.users.grw.linger = lib.mkForce false;

  # Same 256 MB memory discipline as licheerv, minus zram: the live
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

  # Same bring-up-softened watchdog policy as licheerv (hardware WDT TOP
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

  # Cross-compiled on the x86_64 builder; the closure lands in fuckup's
  # /nix/store, which the board already mounts over NFS — activation
  # copies nothing to the 256 MB target. Reachable only from fuckup:
  # 10.55.0.1 is the board end of the point-to-point USB-gadget link
  # (protocol.targetIp in nixos-nanokvm's lib/protocol.nix).
  deployment = {
    targetHost = lib.mkDefault "10.55.0.1";
    targetUser = "grw";
    buildOnTarget = false;
  };
}
