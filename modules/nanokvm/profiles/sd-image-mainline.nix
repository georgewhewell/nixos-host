{ nanokvm }:
# Mainline-kernel SD-card image.
#
# Unlike profiles/sd-image.nix (vendor 5.10 + vendor-FIT), this boots
# the mainline kernel via mainline U-Boot + extlinux: U-Boot's
# distro_bootcmd scans the Btrfs root partition for
# /boot/extlinux/extlinux.conf and loads
# kernel + dtb + initrd from there. fip.bin (mainline U-Boot) lives on
# the FAT firmware partition.
#
# Reachability: the NanoKVM-PCIe board module brings up wired Ethernet in the
# initrd and stage 2. One ECM + ACM gadget remains bound across switch-root;
# stage-2 networkd adopts usb0 without a fragile USB disconnect/re-enumeration.
{
  config,
  lib,
  pkgs,
  rootAuthorizedKeys ? [],
  ...
}: {
  imports = [
    (nanokvm + "/modules/sg2002-sd-image.nix")
    (nanokvm + "/modules/sg2002-usb-gadget-initrd.nix")
  ];

  # Mainline U-Boot + extlinux, NOT the vendor FIT. (platform default
  # is already "mainline"; be explicit so this profile is self-evident.)
  sg2002.uboot = lib.mkForce "mainline";
  sg2002.usbGadget.network.enable = true;
  # Keep one ECM+ACM gadget bound from initrd through stage 2. Detaching an
  # ACM function used as the kernel console can wait indefinitely for a host
  # reader, while resetting DWC2 under ttyGS0 can wedge stage-2 sysinit.
  sg2002.usbGadget.initrd.network.enable = true;
  sg2002.usbGadget.stage2.enable = true;
  # Boards may prefer to rebuild the gadget in stage 2 when they have an
  # independent management path and want stage 2 to own USB explicitly.
  sg2002.usbGadget.stage2.preserveInitrd = lib.mkDefault true;
  # A full DWC2 re-probe tears down the active ACM kernel console. On SG2002
  # that teardown can wedge PID 1's console path; a fleet image then correctly
  # stops feeding its systemd-owned hardware watchdog and resets. Wired
  # Ethernet is the production management path, so leave a wedged ECM RX path
  # wedged instead of risking the whole machine.
  sg2002.usbGadget.stage2.rxGuard.enable = false;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  hardware.deviceTree.enable = true;
  # Same single source of truth as the FIT path: wrap config.sg2002.fdt
  # (set by the platform default + WiFi/OLED/ethernet modules) into the
  # dtbs dir extlinux expects, so the SD image and the USB boot-fit
  # always agree on the DTB.
  hardware.deviceTree.name = "sg2002.dtb";
  hardware.deviceTree.package = lib.mkForce (
    pkgs.runCommand "sg2002-fdt-dir" {} ''
      mkdir -p "$out"
      cp ${config.sg2002.fdt} "$out/sg2002.dtb"
    ''
  );

  # Mirror the kernel console onto the USB gadget serial and keep the
  # OpenSBI firmware region reserved, matching the USB FIT boot path.
  # (sg2002-sd-image.nix already selects the board's physical UART;
  # kernelParams is a merged list.)
  # Keep ttyGS0 as a mirrored kernel-log sink, but put it before the board's
  # physical UART. The final console= entry backs /dev/console; making that a
  # gadget TTY can wedge PID 1 in u_serial gs_close() during shutdown.
  boot.kernelParams = lib.mkBefore (
    [
      # Physical rescue UARTs have explicit getty units in their board modules.
      # Do not create another serial getty for the early UART0 kernel console.
      "systemd.getty_auto=no"
    ]
    ++ lib.optional
      (config.sg2002.consoleDevice != "ttyGS0" && config.sg2002.usbGadget.console.enable)
      "console=ttyGS0,115200"
    ++ ["riscv.fwsz=0x80000"]
  );

  # Kernel logs still reach ACM, but an agetty adds another open/close racing
  # PID 1's console teardown. SSH and the physical UART provide logins.
  systemd.services."serial-getty@ttyGS0".enable = false;

  sg2002.authorizedKeys = rootAuthorizedKeys;
  networking.hostName = lib.mkDefault "nanokvm";

  services.openssh = {
    enable = true;
    # RSA host-key generation consumed more than a minute on the single-core
    # SG2002. Generate one modern, unique key on the device and persist it.
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings.PermitRootLogin = "yes";
    settings.PasswordAuthentication = true;
  };

  users.users.root.initialPassword = "nixos";

  # Keep the native recovery/debug image self-contained.  These are the
  # small interactive tools needed to inspect system pressure and exercise
  # the mainline media graph without borrowing executables over NFS.
  environment.systemPackages = with pkgs; [
    btop
    (v4l-utils.override {
      withGUI = false;
      withBPF = false;
    })
  ];

  services.nanokvm = {
    enable = false;
    openFirewall = false;
  };
}
