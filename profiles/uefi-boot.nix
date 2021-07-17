{ config, pkgs, ... }:

{

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  services.fwupd.enable = true;
  programs.mosh.enable = true;

  nix.extraOptions = ''
    auto-optimise-store = true
  '';

  boot = {
    tmpOnTmpfs = true;
    kernelPackages = pkgs.lib.mkDefault pkgs.linuxPackages-rt_latest;

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
        memtest86.enable = true;
      };
    };

    supportedFilesystems = [ "vfat" "f2fs" ];
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
