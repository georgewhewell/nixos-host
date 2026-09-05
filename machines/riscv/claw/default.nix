# Sipeed LicheeRV-Nano "RV Claw" (SG2002 / RISC-V C906) — the PicoClaw
# expansion unit with the 240x240 ST7789 SPI LCD — USB-booted,
# NFS-rooted fleet member hanging off fuckup's USB port.
#
# Same diskless model as licheerv: each boot is pushed over USB by fuckup's
# usb-boot runner (ROM USB-DL -> FIP -> fastboot FIT), then a one-shot WiFi
# credential crosses that private USB control link. The initrd joins trusted
# house WiFi and mounts /nix/store read-only from trex; USB remains available
# only for control and recovery.
#
# Hardware/boot stack (kernel, DTB, initrd, NFS live root, LCD
# self-test) comes from the nanokvm flake as a module, like licheerv —
# see `sysRiscvClaw` in ../../default.nix. Same dietary constraints:
# 256 MB.
{
  inputs,
  lib,
  network,
  pkgs,
  ...
}:
let
  self = network.hosts.claw;
  clawWifiAddress = network.cidrOf "wifi" self.addresses.wifi;
  clawWifiIp = network.ipOf "wifi" self.addresses.wifi;
  trexIp = network.primaryIp network.hosts.trex;
  protocol = import "${inputs.nanokvm}/lib/protocol.nix";
  runtimeWpaConf = "/run/sg2002-wpa_supplicant.conf";
  wifiConfigReceiver = pkgs.writeText "claw-wifi-config-receiver" ''
    set -eu

    BB=${pkgs.busybox}/bin/busybox
    target=${runtimeWpaConf}
    incoming="''${target}.incoming"
    trap '"$BB" rm -f "$incoming"' EXIT INT TERM

    while :; do
      "$BB" rm -f "$incoming"
      if "$BB" nc -n -l -s ${protocol.targetIp} \
          -p ${toString protocol.ports.wifiConfig} -w 300 > "$incoming"; then
        bytes="$("$BB" wc -c < "$incoming")"
        if [ "$bytes" -gt 0 ] && [ "$bytes" -le 8192 ] \
            && "$BB" grep -q 'ssid=' "$incoming" \
            && "$BB" grep -Eq '^[[:space:]]*(psk|sae_password)=' "$incoming"; then
          "$BB" chmod 0600 "$incoming"
          "$BB" mv "$incoming" "$target"
          trap - EXIT INT TERM
          exit 0
        fi
      fi
    done
  '';
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

  # This board has no usable RTC. The shared USB/NFS live profile keeps the
  # fleet's normal resolver and time daemon enabled, so only order time sync
  # behind the network here; timezone remains inherited from fleet-core.
  systemd.services.systemd-timesyncd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

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

  # USB carries only the stateless ROM/FIT handoff and this one-shot secret.
  # The normal data plane is the onboard AIC8800 on trusted house WiFi; trex
  # serves the read-only Nix store. The WPA3 credential is streamed over the private
  # USB control link into /run, which survives switch-root, so it never enters
  # the Nix store or the FIT image.
  sg2002.bluetooth.enable = true;
  sg2002.wifi = {
    wpaConf = lib.mkForce null;
    wpaConfRuntimePath = runtimeWpaConf;
  };
  nanokvm.nfsLive.server = lib.mkForce trexIp;
  sg2002.watchdogKeeper.healthHost = lib.mkForce trexIp;

  boot.initrd.systemd = {
    storePaths = [ pkgs.busybox wifiConfigReceiver ];
    services = {
      claw-wifi-config = {
        description = "Receive Claw WiFi config over the USB control link";
        wantedBy = [ "initrd.target" ];
        before = [ "wpa_supplicant-wlan0.service" ];
        after = [ "usb-debug-network.service" ];
        wants = [ "usb-debug-network.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.busybox}/bin/busybox sh ${wifiConfigReceiver}";
        };
      };
      "wpa_supplicant-wlan0" = {
        requires = [ "claw-wifi-config.service" ];
        after = [ "claw-wifi-config.service" ];
      };
    };
  };

  boot.initrd.systemd.network.networks."40-wlan0" = {
    matchConfig.Name = "wlan0";
    address = lib.mkForce [ clawWifiAddress ];
    dns = [ (network.gatewayIp "wifi") ];
    routes = [ { Gateway = network.gatewayIp "wifi"; } ];
    networkConfig = {
      DHCP = lib.mkForce "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      KeepConfiguration = "static";
    };
    linkConfig.RequiredForOnline = "no";
  };
  systemd.network.networks."40-wlan0" = {
    matchConfig.Name = "wlan0";
    address = lib.mkForce [ clawWifiAddress ];
    dns = [ (network.gatewayIp "wifi") ];
    routes = [ { Gateway = network.gatewayIp "wifi"; } ];
    networkConfig = {
      DHCP = lib.mkForce "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      KeepConfiguration = "static";
    };
    linkConfig.RequiredForOnline = "no";
  };
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

  # Cross-compiled on the x86_64 builder; trex GC-roots the closure exported
  # to this diskless target.
  deployment = {
    targetHost = lib.mkDefault clawWifiIp;
    targetUser = "grw";
    buildOnTarget = false;
  };
}
