{ nanokvm }:
# USB-recovery NBD-debug profile. Builds on the kernel-test initrd by
# additionally mounting an NBD-served disk image inside the initrd, so
# you can poke at a real filesystem while still living in initramfs.
# Used to isolate "is NBD the problem?" from "is systemd the problem?"
# during stage-2 bring-up.
{...}: {
  imports = [
    (nanokvm + "/modules/sg2002-usb-gadget-initrd.nix")
    ../modules/usb-kernel-test.nix
    ../modules/usb-nbd-debug.nix
  ];

  networking.hostName = "nanokvm-nbd-debug";
}
