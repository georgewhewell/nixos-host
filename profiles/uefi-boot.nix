{pkgs, ...}: {
  boot = {
    tmp.useTmpfs = true;
    kernelPackages = pkgs.lib.mkDefault pkgs.linuxPackages_6_13;
    kernelParams = [
      "msr.allow_writes=on"
      "mitigations=off"
      "panic=30"
    ];

    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
    };

    supportedFilesystems = ["vfat" "f2fs"];
    initrd = {
      supportedFilesystems = [
        "f2fs"
        "nfs"
      ];

      availableKernelModules = [
        "xhci_pci"
        "ehci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "usbhid"
        "sd_mod"
        "sdhci_acpi"
        "r8169"
        "tpm"
        "mii"
        "tpm_tis"
      ];
    };
  };
}
