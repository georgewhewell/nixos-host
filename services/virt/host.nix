{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd.enable = true;

  environment.systemPackages = with pkgs; [
    virtmanager
    virt-viewer
    spice-gtk # fix usb redirect
  ];

  boot.kernelParams = [
    "kvm.report_ignored_msrs=0"
  ];
}
