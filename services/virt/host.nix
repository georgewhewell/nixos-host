{ config, lib, pkgs, ... }:

{
  # 30GB RAM for guests
  boot.kernel.sysctl."vm.nr_hugepages" = 15000;

  imports = [
    ./usb/usb.nix
    ./vfio.nix
  ];

  # Turn on virt
  virtualisation.libvirtd.enable = true;
}
