# Sipeed NanoKVM-PCIe (SG2002 / RISC-V C906).
#
# A regular fleet member: the board's hardware/boot stack (kernel,
# DTB, SD image, nanokvm services) comes from the nanokvm flake as a
# module, and the shared fleet base (`nixosModule`) plus the profiles
# below provide everything else — see `sysRiscvNanokvm` in
# ../../default.nix. The only special treatment is dietary:
# fleet-core.nix instead of common.nix, because 256 MB has no room
# for enableAllFirmware/terminfo/pcscd and friends.
{
  inputs,
  lib,
  network,
  pkgs,
  ...
}: let
  ethHost = network.hosts.nanokvm.addresses.lan;
  wifiHost = network.hosts."nanokvm-wifi".addresses.wifi;
in {
  # Colmena reconstructs nodes through eval-config.nix and therefore does not
  # inherit the nested nixpkgs flake's source metadata automatically. Pin it
  # explicitly so the standalone and hive evaluations are byte-identical.
  system.nixos.revision = lib.mkForce inputs.nanokvm.inputs.nixpkgs.rev;
  system.nixos.versionSuffix = lib.mkForce ".${
    builtins.substring 0 8 inputs.nanokvm.inputs.nixpkgs.lastModifiedDate
  }.${inputs.nanokvm.inputs.nixpkgs.shortRev}";

  imports = [
    inputs.nanokvm.nixosModules.extlinuxTryBoot
    # Fleet identity: grw + sudo, ssh, zsh, /etc/hosts, locale.
    ../../../profiles/fleet-core.nix
    # Keep the 256 MB target out of the normal workstation/server default set:
    # no manuals, installer tools, command-not-found, or default shell helpers.
    ../../../profiles/headless.nix
    # Fleet WiFi: wpa_supplicant on wlan0, PSK from secrets/wifi.yaml.
    ../../../profiles/wireless.nix
    ../../../profiles/watchdog.nix
  ];

  sconfig.profile = "server";

  networking.hostName = "nanokvm";

  # Keep WiFi available as a backup path, but prefer the wired OOB
  # route via the lower metric configured below.
  sg2002.wifi.enable = true;

  # The standalone SD image permits password login for first-boot recovery.
  # A fleet-managed host instead uses the shared grw authorized keys.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;

  # U-Boot/extlinux has no systemd-boot-style automatic boot assessment.
  # This arms a new extlinux DEFAULT as a try-boot after Colmena rewrites
  # extlinux.conf, then blesses it only after the boot survives long enough
  # to be reachable on a management path. The wired OOB segment is
  # currently down network-wide, so accept either wired or WiFi reachability;
  # restore the eth0-only check when the segment is back. The window is
  # short because the 85 s hardware watchdog punishes long unsettled boots.
  boot.extlinuxTryBoot = {
    enable = true;
    timeoutSec = 180;
    successCommand = ''
      systemctl is-active --quiet sshd.service
      if test "$(cat /sys/class/net/eth0/carrier 2>/dev/null || echo 0)" = 1; then
        ip -4 addr show dev eth0 | grep -Fq " ${network.cidrOf "lan" ethHost}"
        ip -4 route get ${network.gatewayIp "lan"} >/dev/null
      else
        ip -4 addr show dev wlan0 | grep -Fq " ${network.cidrOf "wifi" wifiHost}"
      fi
    '';
  };

  # Lingering starts a per-user systemd manager at boot whether or not
  # grw ever logs in — not worth the RAM here.
  users.users.grw.linger = lib.mkForce false;

  # Temporary stability profile while the 256 MB target is being brought
  # up. The journal from the first successful SD boot showed no swap,
  # repeated OOM kills of udev workers, coredump work under memory
  # pressure, and networkd looping on an IPv6 RA MTU the MAC cannot apply.
  zramSwap = {
    enable = true;
    memoryPercent = 75;
  };
  nix = {
    # Colmena builds off-target and only needs the daemon while deploying.
    # Do not run background Nix store maintenance on this SD-card target.
    gc.automatic = lib.mkForce false;
    optimise.automatic = lib.mkForce false;
    registry = lib.mkForce {};
    settings.auto-optimise-store = lib.mkForce false;
  };
  services = {
    logrotate.enable = lib.mkForce false;
    fstrim.enable = lib.mkForce false;
    # baseline.nix default-enables earlyoom; not worth the resident
    # daemon here — zram + the sshd/networkd OOMScoreAdjust floors
    # below are the memory-pressure strategy on 256 MB.
    earlyoom.enable = false;
  };
  security.pam.services.sshd.startSession = lib.mkForce false;
  systemd.services = {
    sshd.serviceConfig.OOMScoreAdjust = lib.mkForce (-1000);
    systemd-networkd.serviceConfig.OOMScoreAdjust = lib.mkForce (-900);
    wpa_supplicant.serviceConfig.OOMScoreAdjust = lib.mkForce (-900);
  };
  # Keep post-mortem evidence without turning the SD card into a log sink.
  # journald stores warning-and-above messages only; persistent storage is
  # capped tightly and notice/info/debug chatter stays out of the journal.
  services.journald.extraConfig = ''
    Storage=persistent
    MaxLevelStore=warning
    SystemMaxUse=8M
    SystemMaxFileSize=2M
    SystemKeepFree=64M
    RuntimeMaxUse=16M
    RuntimeMaxFileSize=4M
    RateLimitIntervalSec=30s
    RateLimitBurst=100
    SyncIntervalSec=5m
  '';
  systemd.coredump.enable = lib.mkForce false;
  services.nanokvm = {
    enable = lib.mkForce true;
    # Bring-up stability: the Go server is the largest resident process
    # on this 256 MB board and the mainline LT6911 generation is
    # reboot-looping in a way that smells like OOM. Keep the compat
    # files/tmpfiles but no daemon until the kernel side is stable,
    # then flip back to true to test HDMI capture.
    server.enable = lib.mkForce false;
    usbGadget.enable = lib.mkForce false;
  };

  # KVM video path: HDMI capture -> Coda980 H.264 -> mediamtx, sharing the
  # fleet-wide interface contract with rock-5b (RTSP :8554/hdmi, WebRTC
  # :8889/hdmi). The bridge publishes over loopback RTSP; mediamtx serves
  # clients. No transcoding anywhere, so this fits in the RAM the Go
  # server is too big for.
  services.mediamtx = {
    enable = true;
    settings = {
      paths = {
        hdmi = {
          source = "publisher";
        };
      };
    };
  };
  networking.firewall.allowedTCPPorts = [8554 8889];
  networking.firewall.allowedUDPPorts = [8189];
  # Memory discipline for the 256 MiB board: the video stack stays out of
  # the boot critical path so the try-boot bless window looks exactly like
  # the previous generation's boot. A first deploy with the stack in the
  # boot path never survived to bless (watchdog reset under the spike) and
  # rolled back every time.
  systemd.services.mediamtx.wantedBy = lib.mkForce [];
  systemd.services.kvm-video = {
    description = "KVM HDMI bridge (capture -> Coda980 H.264 -> mediamtx)";
    # No wantedBy: started by kvm-stack-start once the boot is blessed.
    serviceConfig = {
      # --io dmabuf: raw frames in cached dma-heap buffers imported by the
      # encoder (single SYNC ioctl per frame). --format nv12: the fixed
      # direct input path (0041 linear GDI map) — no kernel staging copy.
      ExecStart = ''
        ${pkgs.sg2002-h264-bridge}/bin/sg2002-h264-bridge \
          /dev/video0 /dev/video1 \
          --size full --io dmabuf --format nv12 \
          --bitrate 4000000 --gop 30 \
          --rtsp rtsp://127.0.0.1:8554/hdmi
      '';
      Restart = "always";
      RestartSec = "2s";
      SupplementaryGroups = ["video"];
      # DeviceAllow turns on the devices cgroup allowlist: the dma-heap
      # nodes must be listed or the dmabuf import path is silently
      # filtered out (EACCES -> mmap fallback -> CMA ENOMEM at 1080p).
      DeviceAllow = [
        "/dev/video0 rw"
        "/dev/video1 rw"
        "/dev/dma_heap/default_cma_region rw"
        "/dev/dma_heap/linux,cma rw"
        "/dev/dma_heap/system rw"
      ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
  systemd.services.kvm-stack-start = {
    description = "Start the KVM video stack once the boot is blessed";
    # Pulled in by the bless unit's wants= below; NOT wantedBy
    # multi-user.target (that plus after=bless forms an ordering cycle:
    # bless itself runs after multi-user).
    after = ["extlinux-try-boot-bless.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl start mediamtx.service kvm-video.service";
    };
  };
  systemd.services.extlinux-try-boot-bless.wants = ["kvm-stack-start.service"];
  # (bless window + network-tolerant successCommand live in the
  # boot.extlinuxTryBoot block above)

  # Keep the SD profile's ECM+ACM gadget continuously bound across
  # switch-root. The NanoKVM compatibility module otherwise defaults to a
  # legacy /boot control file and a second re-enumeration when enabled.
  sg2002.usbGadget.network.controlFile = lib.mkForce null;
  sg2002.usbGadget.stage2.reenumerateAfterBoot.enable = lib.mkForce false;
  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.network.networks = {
    "20-eth0" = {
      address = [
        (network.cidrOf "lan" ethHost)
      ];
      dns = [network.routerIp];
      routes = [
        {
          Gateway = network.gatewayIp "lan";
          Metric = 10;
        }
      ];
      networkConfig = {
        DHCP = lib.mkForce "no";
        IPv6AcceptRA = lib.mkForce false;
      };
      # The SG2002 GMAC has no fused MAC — without this the kernel
      # generates a fresh one every boot. Pin it so neighbors, static
      # DNS, and switch state all identify the OOB wired endpoint.
      # Locally-administered: 02, then "KVM" + .17.
      linkConfig.MACAddress = "02:4b:56:4d:00:17";
    };
    "20-wifi" = {
      address = [
        (network.cidrOf "wifi" wifiHost)
      ];
      dns = [(network.gatewayIp "wifi")];
      routes = [
        {
          Gateway = network.gatewayIp "wifi";
          Metric = 200;
        }
      ];
      networkConfig = {
        DHCP = lib.mkForce "no";
        IPv6AcceptRA = lib.mkForce false;
      };
      linkConfig.RequiredForOnline = lib.mkForce "no";
    };
  };
  # Keep the hardware watchdog, but relax the software panic paths while
  # the board is still in bring-up. First boot can spend a long time
  # resizing, loading SDIO WiFi firmware, and settling udev on 256 MB
  # RAM; panic-on-stall paths make that indistinguishable from a real
  # watchdog reset.
  # The board module owns root filesystem and console parameters. Keep only
  # the fleet's temporary bring-up policy here so storage changes (Btrfs in
  # particular) cannot drift between the image and later Colmena closures.
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
    # This kernel accepts up to 60 here; larger values make
    # systemd-sysctl fail the whole unit.
    "kernel.watchdog_thresh" = lib.mkForce 60;
  };
  systemd.settings.Manager = {
    # The largest SG2002 WDT TOP in the board DT is ~85 s at 25 MHz,
    # so runtime cannot be doubled from 80 s. Keep it at the top end
    # and double the reboot/kexec watchdog windows instead.
    # Keep runtime watchdog active, but avoid the pre-timeout panic path
    # until the boot is stable enough that we can collect logs.
    RuntimeWatchdogSec = lib.mkForce "85s";
    RuntimeWatchdogPreSec = lib.mkForce "off";
    RebootWatchdogSec = lib.mkForce "240s";
    KExecWatchdogSec = lib.mkForce "240s";
  };

  # sops-nix comes from the fleet base (nixosModule + profiles/sops.nix,
  # which points it at the SSH host key). For fresh SD images, run
  # `scripts/nanokvm-inject-sops-key` after writing the image; it
  # installs the stable gitignored host key into /etc/ssh on the SD
  # root so sops-nix can decrypt on first boot.
  sops.useSystemdActivation = true;
  systemd.services.wpa-supplicant-secrets = {
    after = ["sops-install-secrets.service"];
    wants = ["sops-install-secrets.service"];
  };

  # Cross-compiled on the x86_64 builder, so push the closure rather
  # than building on the 256 MB target.
  deployment = {
    # WiFi may live on the isolated VLAN. Deploy over the wired OOB address
    # as the regular fleet user; wheel's passwordless sudo performs activation.
    targetHost = lib.mkDefault (network.ipOf "lan" ethHost);
    targetUser = "grw";
    buildOnTarget = false;
  };
}
