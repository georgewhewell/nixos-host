# Minimal "stay in initrd" target. The initrd brings up the USB ECM
# gadget, configures `10.55.0.1/24`, and exposes the kexec control
# socket on TCP/2325 plus a busybox debug shell on TCP/2323.
#
# Everything interesting comes from `./usb-control.nix`; this module
# just turns on the right knobs.
{...}: {
  imports = [./usb-control.nix];

  config = {
    nanokvm.usbControl = {
      initrd.enable = true;
      inertSwitchRoot.enable = true;
    };
  };
}
