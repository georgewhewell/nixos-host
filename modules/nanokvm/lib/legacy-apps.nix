# Optional fleet-only development frontends. Pass a tree of artifacts built
# from the deployment catalog; these retain the old NBD/kexec workflow.
{ pkgs, protocol, boards }:
let
          usbOledTop = pkgs.writeShellApplication {
            name = "usb-oled-top";
            text = ''
                            case "''${1:-}" in
                              -h|--help)
                                cat <<'EOF'
              Usage: nix run .#usb-oled-top -- [usb-boot options]

              Boots or kexecs the LicheeRV-Nano-W OLED live image and runs top on
              the 128x128 framebuffer via fbcon.

              Defaults:
                --attempts 120
                --rom-dl-timeout 1800
                --wait 120

              Environment overrides:
                NANOKVM_USB_BOOT_ATTEMPTS
                NANOKVM_USB_BOOT_ROM_DL_TIMEOUT
                NANOKVM_USB_BOOT_WAIT
                NANOKVM_NBD_ROOTFS_PORT=auto|0|<port>
                NANOKVM_NBD_ROOTFS_HOST=<target-visible-host-ip>
                NANOKVM_NBD_ROOTFS_BIND=<host-bind-ip>
                NANOKVM_NBD_CLEANUP=0
                NANOKVM_ATTACH=shell|none
                NANOKVM_ON_DETACH=hold|kexec|exit
                NANOKVM_BOOT_MODE=auto|usb|kexec
                NANOKVM_STATUS_LISTEN=1
                USB_IFACE
              EOF
                                exit 0
                                ;;
                            esac

                            usb_iface_present() {
                              local path mac
                              if [ -n "''${USB_IFACE:-}" ]; then
                                [ -d "/sys/class/net/$USB_IFACE" ]
                                return
                              fi

                              for path in /sys/class/net/*; do
                                [ -r "$path/address" ] || continue
                                IFS= read -r mac < "$path/address" || true
                                if [ "$mac" = "${protocol.hostMac}" ]; then
                                  return 0
                                fi
                              done
                              return 1
                            }

                            case "''${NANOKVM_BOOT_MODE:-auto}" in
                              auto|"")
                                if usb_iface_present; then
                                  echo "[usb-oled-top] USB debug interface is present; using kexec"
                                  exec ${boards.licheerv.mainline.live.usb-oled.kexec}/bin/kexec "$@"
                                fi
                                ;;
                              kexec)
                                exec ${boards.licheerv.mainline.live.usb-oled.kexec}/bin/kexec "$@"
                                ;;
                              usb|usb-boot)
                                ;;
                              *)
                                echo "[usb-oled-top] invalid NANOKVM_BOOT_MODE=''${NANOKVM_BOOT_MODE}; expected auto, usb, or kexec" >&2
                                exit 1
                                ;;
                            esac

                            export NANOKVM_ON_DETACH="''${NANOKVM_ON_DETACH:-kexec}"
                            exec ${boards.licheerv.mainline.live.usb-oled.usb-boot}/bin/usb-boot \
                              --attempts "''${NANOKVM_USB_BOOT_ATTEMPTS:-120}" \
                              --rom-dl-timeout "''${NANOKVM_USB_BOOT_ROM_DL_TIMEOUT:-1800}" \
                              --wait "''${NANOKVM_USB_BOOT_WAIT:-120}" \
                              "$@"
            '';
          };
          captureUsbOledTop = pkgs.writeShellApplication {
            name = "capture-usb-oled-top";
            runtimeInputs = with pkgs; [
              asciinema
              asciinema-agg
              coreutils
              git
              gnused
              openssh
              sshpass
            ];
            text = ''
              export NANOKVM_USB_OLED_TOP="''${NANOKVM_USB_OLED_TOP:-${usbOledTop}/bin/usb-oled-top}"
              export NANOKVM_CAPTURE_FONT_DIR="''${NANOKVM_CAPTURE_FONT_DIR:-${pkgs.dejavu_fonts}/share/fonts/truetype}"
              export NANOKVM_CAPTURE_FONT_FAMILY="''${NANOKVM_CAPTURE_FONT_FAMILY:-DejaVu Sans Mono}"
              ${builtins.readFile ../scripts/capture-usb-oled-top.sh}
            '';
          };

in {
  usb-oled-top = usbOledTop;
  capture-usb-oled-top = captureUsbOledTop;
}
