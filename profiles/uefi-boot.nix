{ config, pkgs, ... }:

{
  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  security.rngd.enable = pkgs.lib.mkDefault true;

  boot = {
    tmpOnTmpfs = true;
    kernelPackages = pkgs.linuxPackages_latest;

    loader = {
      grub = {
        efiSupport = true;
        devices = [ "nodev" ];
        zfsSupport = true;
        copyKernels = true;
	  extraEntries = ''
	    menuentry "Reboot" {
	      reboot
	    }
	    menuentry "Poweroff" {
	      halt
	    }
	  '';
      };
      efi.canTouchEfiVariables = true;
    };

    initrd = {
   network = {
     enable = true;
     # This will use udhcp to get an ip address.
     # Make sure you have added the kernel module for your network driver to `boot.initrd.availableKernelModules`, 
     # so your initrd can load it!
     # Static ip addresses might be configured using the ip argument in kernel command line:
     # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
     # this will automatically load the zfs password prompt on login
     # and kill the other prompt so boot can continue
     postCommands = ''
       echo "zfs load-key -a; killall zfs" >> /root/.profile
     '';
   };
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
