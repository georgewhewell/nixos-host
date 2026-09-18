# Bash helper shared by host-side runners.  A target that watchdog-resets after
# kernel handoff returns to the CV181x BootROM as USB 3346:1000; callers should
# stop waiting for the dead target and let their service retry the uploader.
''
  cv181x_rom_present() {
    local root="''${CV181X_USB_SYSFS_ROOT:-/sys/bus/usb/devices}"
    local device vendor product

    shopt -s nullglob
    for device in "$root"/*; do
      [ -r "$device/idVendor" ] || continue
      [ -r "$device/idProduct" ] || continue
      read -r vendor < "$device/idVendor" || continue
      read -r product < "$device/idProduct" || continue
      if [ "$vendor:$product" = 3346:1000 ]; then
        return 0
      fi
    done
    return 1
  }
''
