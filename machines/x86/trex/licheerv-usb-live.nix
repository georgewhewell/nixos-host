# Host-side serving for the camera-equipped LicheeRV Nano attached to trex.
#
# A persistent poller and a ROM udev trigger both feed the same singleton
# service. It pushes FIP -> fastboot -> the fleet licheerv FIT, configures
# trex's end of the USB Ethernet link as 10.55.0.2, and leaves the target
# running from trex's existing read-only NFSv4 /nix/store export.
{ pkgs, inputs, ... }:
let
  nanokvmLib = inputs.nanokvm.inputs.nixpkgs.lib;
  protocol = import "${inputs.nanokvm}/lib/protocol.nix";
  hostShellPrelude = import "${inputs.nanokvm}/lib/host-prelude.nix" protocol;
  art = (import "${inputs.nanokvm}/lib/artifacts.nix" {
    lib = nanokvmLib;
    inherit hostShellPrelude;
  }) pkgs;

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
    waitForSsh = true;
  };
  licheervBoot = pkgs.writeShellScript "licheerv-usb-boot" ''
    if ${pkgs.iputils}/bin/ping -c 1 -W 1 10.55.0.1 >/dev/null 2>&1; then
      echo "[licheerv-usb-boot] target already reachable at 10.55.0.1"
      exit 0
    fi
    exec ${licheervUsbLive}/bin/usb-boot --rom-dl-verbose
  '';
in
{
  # profiles/nas.nix and profiles/netboot-server.nix already provide the
  # fsid=0 pseudo-root, the read-only 10.55.0.0/24 store export, and the
  # /export/nix-store bind mount. Do not declare a competing NFS server here.

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
