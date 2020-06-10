{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";
  boot.kernelParams = [ "cma=786M" ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_amlogic;
  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];
  /*
    services.xserver.extraConfig = ''
      Section "OutputClass"
        Identifier "Meson"
        MatchDriver "meson"
        Driver "modesetting"
        Option "PrimaryGPU" "true"
      EndSection
    ''; */

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];

  imports = [
    ../common.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/tvbox-gbm.nix
  ];
}
