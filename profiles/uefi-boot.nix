{ config, pkgs, ... }:

{

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

#  security.rngd.enable = pkgs.lib.mkDefault true;
  services.fwupd.enable = true;

  /*
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    };
    */

  programs.mosh.enable = true;

  nix.extraOptions = ''
    auto-optimise-store = true
  '';

  boot = {
    tmpOnTmpfs = true;
    kernelPackages = pkgs.lib.mkDefault pkgs.linuxPackages_latest;

    kernelParams = [
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

    initrd = {
      supportedFilesystems = [
        #"zfs"
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
