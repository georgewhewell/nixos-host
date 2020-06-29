{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd = {
    enable = true;
    qemuVerbatimConfig = ''
      namespaces = []

      # Whether libvirt should dynamically change file ownership
      dynamic_ownership = 0
    '';
  };

  environment.systemPackages = with pkgs; [
    virtmanager
    virt-viewer
    spice-gtk # fix usb redirect
  ];

  boot.kernelParams = [
    "kvm.report_ignored_msrs=0"
  ];
}
