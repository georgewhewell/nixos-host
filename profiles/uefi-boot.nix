{pkgs, ...}: {
  boot = {
    tmp.useTmpfs = true;
    # use higher prio than default to avoid conflicts
    kernelPackages = pkgs.lib.mkOverride 999 pkgs.linuxPackages_latest;
    kernelParams = [
      "msr.allow_writes=on"
      "mitigations=off"
    ];

    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot = {
        enable = true;
        configurationLimit = 4;
      };
    };

    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ehci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        # USB Attached SCSI: required for root on a UAS enclosure (e.g. strix-1's
        # SSD moved from M.2 into an ASM246X USB bridge). Without it stage-1 can
        # bring up xhci but never binds the disk, and root fails to mount.
        "uas"
        "usbhid"
        "sd_mod"
        "sdhci_acpi"
      ];
    };
  };
}
