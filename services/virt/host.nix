{ config, lib, pkgs, ... }:

{
  # 30GB RAM for guests
  boot.kernel.sysctl."vm.nr_hugepages" = 10000;

  imports = [
    ./vfio.nix
  ];

  # Turn on virt
  virtualisation.libvirtd.enable = true;
}
