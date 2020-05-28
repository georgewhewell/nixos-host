{ config, pkgs, lib, ... }:

{
  networking.hostName = "amlogic-s912";
  boot.kernelParams = [ "cma=384M" ];

  hardware.firmware = with pkgs; [ meson-firmware armbian-firmware ];

  services.xserver.extraConfig = ''
    Section "OutputClass"
    	Identifier "Meson"
    	MatchDriver "meson"
    	Driver "modesetting"
    	Option "PrimaryGPU" "true"
    EndSection
  '';

  # make /dev/dri0 be panfrost?
  boot.initrd.availableKernelModules = [ "panfrost" ];

  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor (pkgs.linux_testing.override {
    argsOverride = rec {
      src = pkgs.fetchFromGitHub {
        owner = "150balbes";
        repo = "Amlogic_s905-kernel";
        rev = "5dc4b922d617a74d0ee3acc6c1649c5e4a1ea956";
        sha256 = "0m08v5b36f541546604nyxvi8rq7n98hbbg9iz7zcz8284c2j7vi";
      };
      version = "5.7-rc6";
      modDirVersion = "5.7.0-rc6";
    };
  }));

  boot.kernelPatches = [
     {
       name = "media";
       patch = null;
       extraConfig = ''
         STAGING_MEDIA y
       '';
     }
  ];

  imports = [
    ../common.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/tvbox.nix
  ];
}
