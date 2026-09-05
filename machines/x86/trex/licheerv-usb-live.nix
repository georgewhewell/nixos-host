# Host-side serving for the camera-equipped LicheeRV Nano attached to trex.
#
# A persistent poller and a ROM udev trigger both feed the same singleton
# service. It pushes FIP -> fastboot -> the fleet licheerv FIT; the target then
# DHCPs its RJ45 and runs from trex's read-only NFSv4 /nix/store export. The
# USB Ethernet gadget remains a private control/recovery link.
{ lib, pkgs, inputs, network, ... }:
let
  nanokvmLib = inputs.nanokvm.inputs.nixpkgs.lib;
  protocol = import "${inputs.nanokvm}/lib/protocol.nix";
  hostShellPrelude = import "${inputs.nanokvm}/lib/host-prelude.nix" protocol;
  art = (import "${inputs.nanokvm}/lib/artifacts.nix" {
    lib = nanokvmLib;
    inherit hostShellPrelude;
  }) pkgs;
  licheervIp = network.primaryIp network.hosts.licheerv;

  licheervCfg = inputs.self.nixosConfigurations.licheerv;
  licheervUsbLive = art.mkNfsUsbBootRunner {
    name = "usb-boot";
    fit = art.mkBootFit {
      cfg = licheervCfg;
      profile = "live";
      description = "SG2002 USB NFS live boot (licheerv camera, fleet)";
    };
    bootargs = art.mkLiveBootargs {
      cfg = licheervCfg;
      # Nobody drains ttyGS0 during unattended boot. A blocked gadget
      # console can stop this small system before network userspace starts.
      usbConsole = false;
      extra = [
        "systemd.getty_auto=no"
        "udev.children_max=2"
        "cpuidle.off=1"
      ];
    };
    nfsServer = licheervCfg.config.nanokvm.nfsLive.server;
    nfsExport = licheervCfg.config.nanokvm.nfsLive.storeExport;
    # The reliable data path is Ethernet; the generic runner's SSH check is
    # pinned to the optional USB control address, so validate LAN SSH below.
    waitForSsh = false;
  };
  licheervBoot = pkgs.writeShellScript "licheerv-usb-boot" ''
    if ${pkgs.iputils}/bin/ping -c 1 -W 1 ${lib.escapeShellArg licheervIp} >/dev/null 2>&1; then
      echo "[licheerv-usb-boot] target already reachable over Ethernet at ${licheervIp}"
      exit 0
    fi
    if ${pkgs.iputils}/bin/ping -c 1 -W 1 10.55.0.1 >/dev/null 2>&1; then
      echo "[licheerv-usb-boot] target already reachable at 10.55.0.1"
      exit 0
    fi
    # A software reset can take more than one pyserial scan to shed the old
    # gadget and expose the ROM ACM node. Wait long enough for unattended
    # recovery; the downloader starts an attempt's protected transfer window
    # only after it has actually observed the ROM device.
    ${licheervUsbLive}/bin/usb-boot \
      --rom-dl-verbose --rom-dl-timeout 900 --attempts 10 || exit $?

    echo "[licheerv-usb-boot] waiting for SSH over Ethernet at ${licheervIp}..."
    for _attempt in {1..180}; do
      if ${pkgs.netcat-openbsd}/bin/nc -z -w 1 ${lib.escapeShellArg licheervIp} 22 >/dev/null 2>&1; then
        echo "[licheerv-usb-boot] SSH is up over Ethernet at ${licheervIp}"
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "[licheerv-usb-boot] Ethernet SSH did not answer at ${licheervIp}" >&2
    exit 1
  '';
in
{
  # profiles/nas.nix and profiles/netboot-server.nix already provide the
  # fsid=0 pseudo-root, the read-only 10.55.0.0/24 store export, and the
  # /export/nix-store bind mount. Do not declare a competing NFS server here.

  # The camera target publishes its already-encoded H.264 stream over RJ45.
  # MediaMTX on trex exposes one stable RTSP source for go2rtc.
  services.mediamtx = {
    enable = true;
    settings = {
      # This relay is intentionally RTSP-only. The default HLS listener
      # collides with trex's existing service on 127.0.0.1:8888, while RTMP,
      # WebRTC and SRT are unnecessary extra listeners for the go2rtc path.
      rtmp = false;
      hls = false;
      webrtc = false;
      srt = false;
      paths.licheerv.source = "publisher";
    };
  };
  networking.firewall.allowedTCPPorts = [ 8554 ];

  # Keep the optional USB control gadget out of trex's generic CDC-to-br0.lan
  # policy. It is no longer the NFS or video transport, but remains useful for
  # recovery and must not be accidentally bridged onto the LAN.
  systemd.network.networks."20-licheerv-usb" = {
    matchConfig.MACAddress = protocol.hostMac;
    address = [ "${protocol.hostIp}/${protocol.prefix}" ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      IgnoreCarrierLoss = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  systemd.tmpfiles.rules = [
    "L+ /var/lib/licheerv-usb-live - - - - ${licheervUsbLive}"
  ];

  # Keep cdc_acm bound: cv181x-rom-dl communicates through the ttyACM node
  # created for the 3346:1000 BootROM device. ModemManager may ignore it;
  # removing the driver removes the upload transport itself.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="3346", ATTR{idProduct}=="1000", TAG+="systemd", ENV{SYSTEMD_WANTS}="licheerv-usb-boot.service", ENV{ID_MM_DEVICE_IGNORE}="1"
  '';

  systemd.services.licheerv-usb-boot = {
    description = "USB-boot the camera LicheeRV Nano into its NFS live system";
    # wantedBy catches a board already in ROM mode during trex boot; the udev
    # rule catches later plugs and resets. systemd keeps this a singleton.
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = licheervBoot;
      Environment = [
        "NANOKVM_ATTACH=none"
      ];
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };
}
