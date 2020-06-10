{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.usb-gadget;
in
{

  options = {

    usb-gadget = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Create libcomposite gadgets from initrd
        '';
      };

      initrdDHCP = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Get DHCP lease in initrd
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable rec {

    console.extraTTYs = [ "ttyGS0" ];

    boot.initrd.availableKernelModules = [
      "g_ether"
      "libcomposite"
      "udc-core"
      "usb_f_acm"
      "usb_f_acm"
      "usb_f_rndis"
      "usb_f_iacm"
      "u_ether"
      "u_serial"
      "r8152"
      "dwc2"
      "configfs"
    ];

    boot.initrd.kernelModules = [ "libcomposite" "dwc2" "musb_hdrc" ];
    boot.initrd.preLVMCommands =
      let
        udhcpcScript =
          pkgs.writeScript "udhcp-script"
            ''
              #! /bin/sh
              if [ "$1" = bound ]; then
                ip address add "$ip/$mask" dev "$interface"
                if [ -n "$router" ]; then
                  ip route add default via "$router" dev "$interface"
                fi
                if [ -n "$dns" ]; then
                  rm -f /etc/resolv.conf
                  for i in $dns; do
                    echo "nameserver $dns" >> /etc/resolv.conf
                  done
                fi
              fi
            '';
      in
      lib.mkBefore ''
        START_DIR=$(pwd)

        echo "Setting up USB gadget"
        udevadm settle

        mkdir -p /sys/kernel/config
        mount -t configfs none /sys/kernel/config

        cd /sys/kernel/config/usb_gadget/
        mkdir g && cd g

        echo 0x1d6b > idVendor  # Linux Foundation
        echo 0x0104 > idProduct # Multifunction Composite Gadget
        echo 0x0100 > bcdDevice # v1.0.0
        echo 0x0200 > bcdUSB    # USB 2.0

        mkdir -p strings/0x409
        echo "deadbeef00115599"    > strings/0x409/serialnumber
        echo "NixOS-Embedded"      > strings/0x409/manufacturer
        echo "Net/Serial Gadget"   > strings/0x409/product

        mkdir -p functions/acm.usb0    # serial
        mkdir -p functions/rndis.usb0  # network

        mkdir -p configs/c.1
        echo 500 > configs/c.1/MaxPower
        ln -s functions/rndis.usb0 configs/c.1/
        ln -s functions/acm.usb0   configs/c.1/

        # make sure udc is created..
        udevadm settle -t 5

        ls /sys/class/udc/ > UDC

        # make sure interface exists before continue
        udevadm settle -t 5
        echo "Gadget created"

        ${lib.optionals cfg.initrdDHCP ''
          echo "Looking for DHCP on usb0"
          ip link set usb0 up
          udhcpc --quit --now --script ${udhcpcScript} -i usb0 && hasNetwork=1
        ''}

        cd $START_DIR
      '';
  };

  meta = { };
}
