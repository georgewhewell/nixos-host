{ config, pkgs, ... }:

{

  boot = {
    tmpOnTmpfs = true;

    zfs.enableUnstable = true;
    kernelPackages = pkgs.linuxPackages_latest;

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      supportedFilesystems = [
        "zfs"
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

  services.fwupd.enable = true;
}
