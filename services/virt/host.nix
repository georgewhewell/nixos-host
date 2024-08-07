{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "start";
    allowedBridges = [ "br0" ];
    qemu = {
      ovmf.enable = true;
      swtpm.enable = true;
      verbatimConfig = ''
        namespaces = []

        # Whether libvirt should dynamically change file ownership
        dynamic_ownership = 0
      '';
    };
  };

  programs.virt-manager.enable = true;

  # /*
  environment.systemPackages = with pkgs; [
    # virt-manager
    # virt-viewer
    spice-gtk # fix usb redirect
    mstflint # mlx firmware
    pciutils
  ];
  # */
  boot.kernelParams = [
    # Use IOMMU
    # "intel_iommu=on"

    # Needed by OS X
    "kvm.ignore_msrs=1"
    "vfio_iommu_type1.allow_unsafe_interrupts=1"
  ];

  environment.etc."qemu-ifup" = rec {
    target = "qemu-ifup";
    text = ''
      #!${pkgs.stdenv.shell}
      echo "Executing ${target}"
      echo "Bringing up $1 for bridged mode..."
      ${pkgs.iproute2}/bin/ip link set $1 up promisc on
      echo "Adding $1 to br0.lan..."
      ${pkgs.bridge-utils}/bin/brctl addif br0.lan $1
      sleep 2
    '';
    mode = "0744";
    uid = config.ids.uids.root;
  };

  boot.kernelModules = [
    "vfio"
    "vfio_pci"
    # "vfio_iommu_type1"
  ];
}
