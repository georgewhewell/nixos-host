# Sipeed LicheeRV-Nano-W (SG2002 / RISC-V C906) — USB-booted, Ethernet
# NFS-rooted camera node. USB delivers the boot image; RJ45 carries data.
#
# Unlike nanokvm (SD card + extlinux), this board has no local boot
# medium in play: each boot is pushed over USB (rom-dl FIP + fastboot
# FIT from trex), the initrd DHCPs eth0 and mounts /nix/store from trex's
# LAN address, and stage 2 runs from that. The private USB gadget remains a
# control/recovery path but is not the live root or camera transport. The
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
  pkgs,
  ...
}:
let
  licheervIp = network.primaryIp network.hosts.licheerv;
  trexIp = network.primaryIp network.hosts.trex;
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

  networking.hostName = "licheerv";

  # WiFi stays off: this unit's AIC8800 ships the same burned-in default
  # MAC as nanokvm's (38:7a:cc:40:41:e3), so both on the wifi VLAN would
  # collide. The NFS root and camera stream use the wired Ethernet link.
  sg2002.wifi.enable = lib.mkForce false;

  # Fleet hosts are key-only (fleet-core). The live profile's first-boot
  # password path stays as a local recovery fallback only.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;

  # This is not a KVM: no nanokvm server or HDMI pipeline. The GC4653 is
  # captured as packed RAW12, demosaiced/downscaled to 640x360 NV12, encoded
  # by Coda980, and published to mediamtx on trex over wired Ethernet.
  services.nanokvm.enable = lib.mkForce false;

  environment.systemPackages = [
    pkgs.sg2002-h264-bridge
    (pkgs.v4l-utils.override {
      withGUI = false;
      withBPF = false;
    })
  ];

  systemd.services.licheerv-camera = {
    description = "GC4653 camera bridge (RAW12 -> NV12 -> Coda H.264 -> trex)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig = {
      # CSI can return EIO on the first cold-boot STREAMON while its clocks
      # settle. Retry forever; parking the camera after three starts defeats
      # an otherwise unattended node.
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      # The initrd-to-stage2 handoff can lose udev's device-unit activation
      # event even though the character nodes appear normally. Poll the nodes
      # themselves instead of waiting forever on dev-video1.device.
      ExecStartPre = pkgs.writeShellScript "licheerv-camera-wait-for-video" ''
        for _attempt in {1..180}; do
          if [[ -c /dev/video0 && -c /dev/video1 ]]; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "timed out waiting for /dev/video0 and /dev/video1" >&2
        exit 1
      '';
      ExecStart = ''
        ${pkgs.sg2002-h264-bridge}/bin/sg2002-h264-bridge \
          /dev/video0 /dev/video1 \
          --io mmap --scaler cpu --capture-buffers 2 --format nv12 \
          --bitrate 2000000 --gop 30 \
          --rtsp rtsp://${trexIp}:8554/licheerv
      '';
      Restart = "always";
      RestartSec = "5s";
      TimeoutStartSec = "210s";
      SupplementaryGroups = [ "video" ];
      DeviceAllow = [
        "/dev/video0 rw"
        "/dev/video1 rw"
      ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

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

  # Keep the DHCP identity stable in both initrd and stage 2. The SG2002 GMAC
  # has no fused address and otherwise rolls a random one every boot.
  boot.initrd.systemd.network.networks."20-eth0".linkConfig.MACAddress =
    network.hosts.licheerv.mac;
  systemd.network.networks."20-eth0".linkConfig.MACAddress = network.hosts.licheerv.mac;

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
  # The board's usb-control module owns the watchdog policy for live boots.
  # Its independent keeper arms when trex answers (or after a bounded startup
  # grace), then releases the hardware watchdog after sustained host loss so a
  # wedged Ethernet/NFS target returns to ROM for an automatic download.

  # Cross-compiled on the x86_64 builder; the closure lands in the
  # trex's /nix/store, which the board already mounts over NFS — activation
  # copies nothing to the 256 MB target.
  deployment = {
    targetHost = lib.mkDefault licheervIp;
    targetUser = "grw";
    buildOnTarget = false;
  };
}
