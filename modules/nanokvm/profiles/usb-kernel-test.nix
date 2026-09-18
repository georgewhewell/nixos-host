{ nanokvm }:
# USB-recovery kernel-only test profile. Boots a kernel + initrd to
# RAM via fastboot; the initrd brings up USB ECM (10.55.0.1/24) plus a
# kexec control socket and a busybox debug shell. The goal isn't to
# reach userspace — it's to validate that a particular kernel boots on
# the SoC at all, and to act as the kexec source for deploying a real
# stage-2 root.
{...}: {
  imports = [
    (nanokvm + "/modules/sg2002-usb-gadget-initrd.nix")
    ../modules/usb-kernel-test.nix
  ];

  networking.hostName = "nanokvm-kernel-test";
}
