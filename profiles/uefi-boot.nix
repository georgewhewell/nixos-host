{pkgs, ...}: {
  boot = {
    tmp.useTmpfs = true;
    # use higher prio than default to avoid conflicts
    kernelPackages = pkgs.lib.mkOverride 999 pkgs.linuxPackages_latest;
    kernelParams = [
      "msr.allow_writes=on"
      "mitigations=off"
      "panic=5"
      # NMI watchdog for hard lockup detection (x86-specific)
      # panic is part of nmi_watchdog= syntax; hardlockup_panic= is not a
      # kernel command-line parameter on current Linux.
      "nmi_watchdog=panic,1"
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
