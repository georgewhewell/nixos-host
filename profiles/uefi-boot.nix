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
        configurationLimit = 10;
      };
    };

    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ehci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "usbhid"
        "sd_mod"
        "sdhci_acpi"
      ];
    };
  };
}
