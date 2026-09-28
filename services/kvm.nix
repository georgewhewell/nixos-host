{
  config,
  lib,
  network,
  pkgs,
  ...
}: let
  # Signed recovery UKIs embed a host identity. Keep this aligned with the
  # physical HDMI/OTG cable and provision the matching image on the KVM.
  targetHost = config.services.kvmBootstrap.targetHost;
  secureHosts = lib.filterAttrs (_: h: h.strix.secureBoot or false) network.hosts;
in {
  options.services.kvmBootstrap.imageFile = lib.mkOption {
    type = lib.types.str;
    default = "/var/lib/kvm-bootstrap/${targetHost}-secure.img";
    description = ''
      Read-only GPT recovery image exposed over USB. For a Secure Boot target,
      provision a signed UKI image with strix-secure-boot-recovery and select
      its persistent absolute path here. Never put private signing keys on
      the KVM. The public enrollment certificate is included in that image.
    '';
  };
  options.services.kvmBootstrap.targetHost = lib.mkOption {
    type = lib.types.enum (builtins.attrNames secureHosts);
    default = "strix-2";
    example = "strix-1";
    description = ''
      Secure Boot host attached to the KVM's HDMI/OTG cable. The signed
      recovery image embeds its host identity, so an image for another host
      would boot the attached machine with that host's network and storage
      configuration. Provision the matching image whenever moving the cable.
    '';
  };

  config = {
    # Stable symlinks for RK3588 video devices (mainline drivers).
    # ATTR{name} values verified against the live v4l2 device names:
    # /dev/video5 name is "stream_hdmirx" (snps_hdmirx is the platform
    # driver name, not the v4l2 name); /dev/video3 is the hantro-driven
    # VEPU121 encoder node (JPEG only in mainline — kept for future use).
    services.udev.extraRules = ''
      SUBSYSTEM=="video4linux", ATTR{name}=="stream_hdmirx", SYMLINK+="hdmi-rx"
      SUBSYSTEM=="video4linux", ATTR{name}=="rockchip,rk3588-vepu121-enc", SYMLINK+="video-enc"
    '';

    # HDMI-in capture → RTSP/WebRTC stream via mediamtx (on-demand).
    # Mainline-only path: snps_hdmirx gives BGR24 multiplanar at the
    # source's native DV timings (4K30 currently); the VEPU121 encoder
    # node is JPEG-only under mainline hantro, so H.264 is libx264
    # software encode. User-authorized fallback: downscale to 1080p
    # (4K ultrafast measured ~22fps on ~6 of 8 cores — antisocial on
    # this buildfarm slave; 1080p costs ~1-2 cores at full rate).
    services.mediamtx = {
      enable = true;
      allowVideoAccess = true;
      settings = {
        paths = {
          hdmi = {
            source = "publisher";
            runOnDemand = "${pkgs.writeShellScript "kvm-hdmi-capture" ''
              set -u

              ffmpeg_pid=
              cleanup() {
                trap - INT TERM EXIT
                if [ -n "$ffmpeg_pid" ] && kill -0 "$ffmpeg_pid" 2>/dev/null; then
                  kill -TERM "$ffmpeg_pid" 2>/dev/null || true
                  remaining=20
                  while kill -0 "$ffmpeg_pid" 2>/dev/null && [ "$remaining" -gt 0 ]; do
                    ${pkgs.coreutils}/bin/sleep 0.1
                    remaining=$((remaining - 1))
                  done
                  kill -KILL "$ffmpeg_pid" 2>/dev/null || true
                  wait "$ffmpeg_pid" 2>/dev/null || true
                fi
              }
              trap 'cleanup; exit 0' INT TERM
              trap cleanup EXIT

              ${pkgs.v4l-utils}/bin/v4l2-ctl -d /dev/hdmi-rx --set-dv-bt-timings query
              ${pkgs.ffmpeg-headless}/bin/ffmpeg \
                -hide_banner -loglevel warning \
                -f v4l2 -input_format bgr24 -i /dev/hdmi-rx \
                -vf scale=1920:1080,format=nv12 \
                -c:v libx264 -preset ultrafast -tune zerolatency \
                -b:v 4M -maxrate 6M -bufsize 8M -g 60 \
                -an -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:8554/hdmi &
              ffmpeg_pid=$!
              status=0
              wait "$ffmpeg_pid" || status=$?
              ffmpeg_pid=
              trap - EXIT
              exit "$status"
            ''}";
            runOnDemandCloseAfter = "5s";
          };
        };
      };
    };

    # mediamtx: 8554 RTSP, 8889 WebRTC HTTP, 8189/UDP WebRTC ICE
    networking.firewall.allowedTCPPorts = [8554 8889];
    networking.firewall.allowedUDPPorts = [8189];

    # USB OTG composite gadget exposed to the controlled host:
    #   - ECM   (CDC ethernet, lets host reach rock-5b over USB)
    #   - HID 0 (boot keyboard, 8-byte reports → /dev/hidg0)
    #   - HID 1 (boot mouse,    4-byte reports → /dev/hidg1)
    #   - read-only signed UKI recovery disk for services.kvmBootstrap.targetHost
    boot.kernelModules = ["libcomposite" "usb_f_mass_storage"];

    systemd.services.kvm-usb-gadget = {
      description = "KVM USB composite gadget (ECM + HID + iPXE disk)";
      wantedBy = ["multi-user.target"];
      after = ["sys-kernel-config.mount" "systemd-modules-load.service"];
      requires = ["sys-kernel-config.mount"];
      unitConfig.RequiresMountsFor = [ config.services.kvmBootstrap.imageFile ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "kvm-gadget-up" ''
          set -eu
          cd /sys/kernel/config/usb_gadget

          # Idempotent teardown if a previous instance is around.
          if [ -d g1 ]; then
            echo "" > g1/UDC 2>/dev/null || true
            rm -f g1/configs/c.1/ecm.usb0 g1/configs/c.1/hid.usb0 g1/configs/c.1/hid.usb1 g1/configs/c.1/mass_storage.usb0 || true
            rmdir g1/configs/c.1/strings/* 2>/dev/null || true
            rmdir g1/configs/c.1 2>/dev/null || true
            rmdir g1/functions/* 2>/dev/null || true
            rmdir g1/strings/* 2>/dev/null || true
            rmdir g1 2>/dev/null || true
          fi

          mkdir g1
          cd g1

          echo 0x1d6b > idVendor
          echo 0x0104 > idProduct
          echo 0x0100 > bcdDevice
          echo 0x0200 > bcdUSB

          mkdir -p strings/0x409
          echo 'rock5b001'   > strings/0x409/serialnumber
          echo 'satanic'     > strings/0x409/manufacturer
          echo 'rock-5b kvm' > strings/0x409/product

          mkdir -p configs/c.1/strings/0x409
          echo 'KVM' > configs/c.1/strings/0x409/configuration
          echo 250   > configs/c.1/MaxPower

          mkdir -p functions/ecm.usb0
          ln -s functions/ecm.usb0 configs/c.1/ecm.usb0

          # Boot keyboard: standard 63-byte report descriptor, 8-byte reports
          # (modifier + reserved + 6 keycodes).
          mkdir -p functions/hid.usb0
          echo 1 > functions/hid.usb0/protocol
          echo 1 > functions/hid.usb0/subclass
          echo 8 > functions/hid.usb0/report_length
          printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > functions/hid.usb0/report_desc
          ln -s functions/hid.usb0 configs/c.1/hid.usb0

          # Boot mouse: 52-byte descriptor, 4-byte reports
          # (buttons + dx + dy + wheel).
          mkdir -p functions/hid.usb1
          echo 2 > functions/hid.usb1/protocol
          echo 1 > functions/hid.usb1/subclass
          echo 4 > functions/hid.usb1/report_length
          printf '\x05\x01\x09\x02\xa1\x01\x09\x01\xa1\x00\x05\x09\x19\x01\x29\x03\x15\x00\x25\x01\x95\x03\x75\x01\x81\x02\x95\x01\x75\x05\x81\x03\x05\x01\x09\x30\x09\x31\x09\x38\x15\x81\x25\x7f\x75\x08\x95\x03\x81\x06\xc0\xc0' > functions/hid.usb1/report_desc
          ln -s functions/hid.usb1 configs/c.1/hid.usb1

          # A UEFI-removable disk whose only payload is full iPXE with its
          # native NIC drivers.  ro=1 protects the immutable Nix-store image.
          mkdir functions/mass_storage.usb0
          echo 1 > functions/mass_storage.usb0/lun.0/ro
          echo 1 > functions/mass_storage.usb0/lun.0/removable
          echo ${lib.escapeShellArg config.services.kvmBootstrap.imageFile} > functions/mass_storage.usb0/lun.0/file
          ln -s functions/mass_storage.usb0 configs/c.1/mass_storage.usb0

          ls /sys/class/udc > UDC
        '';
        ExecStop = pkgs.writeShellScript "kvm-gadget-down" ''
          set -u
          cd /sys/kernel/config/usb_gadget
          if [ -d g1 ]; then
            echo "" > g1/UDC 2>/dev/null || true
            rm -f g1/configs/c.1/ecm.usb0 g1/configs/c.1/hid.usb0 g1/configs/c.1/hid.usb1 g1/configs/c.1/mass_storage.usb0 || true
            rmdir g1/configs/c.1/strings/* 2>/dev/null || true
            rmdir g1/configs/c.1 2>/dev/null || true
            rmdir g1/functions/* 2>/dev/null || true
            rmdir g1/strings/* 2>/dev/null || true
            rmdir g1 2>/dev/null || true
          fi
        '';
      };
    };

    # FAEX9's warm reboot leaves an already-connected composite gadget at USB
    # state "default" and never addresses it again.  Simulate the cable pulse
    # that makes the firmware enumerate it.  Other transient states and a fully
    # configured host are deliberately left alone.
    systemd.services.kvm-usb-reenumerate = {
      description = "Re-enumerate a KVM USB gadget stuck across host reboot";
      wantedBy = ["multi-user.target"];
      after = ["kvm-usb-gadget.service"];
      bindsTo = ["kvm-usb-gadget.service"];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 1;
        ExecStart = pkgs.writeShellScript "kvm-gadget-reenumerate" ''
          set -eu
          gadget=/sys/kernel/config/usb_gadget/g1
          udc="$(${pkgs.coreutils}/bin/cat "$gadget/UDC")"
          default_samples=0

          while true; do
            state="$(${pkgs.coreutils}/bin/cat "/sys/class/udc/$udc/state")"
            if [ "$state" = default ]; then
              default_samples=$((default_samples + 1))
            else
              default_samples=0
            fi

            if [ "$default_samples" -ge 10 ]; then
              echo "Host left $udc in USB default state; re-enumerating gadget"
              echo "" > "$gadget/UDC"
              ${pkgs.coreutils}/bin/sleep 0.25
              echo "$udc" > "$gadget/UDC"
              default_samples=0
            fi

            ${pkgs.coreutils}/bin/sleep 0.2
          done
        '';
        };
      };
  };
}
