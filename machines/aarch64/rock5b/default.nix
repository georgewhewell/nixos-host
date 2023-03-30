{ config, pkgs, lib, ... }:

{

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/nas-mounts.nix
      ../../../services/buildfarm-slave.nix
      ../../../profiles/tvbox-gbm.nix
    ];

  sconfig = {
    profile = "desktop";
    home-manager.enable = true;
    home-manager.enableGraphical = false;
  };

  deployment.targetHost = "rock5b";

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
      enabledCollectors = [ "systemd" ];
    };
  };

  zramSwap = {
    enable = true;
    priority = 10;
    algorithm = "lz4";
    swapDevices = 4;
    memoryPercent = 30;
    memoryMax = 4 * 1024 * 1024;
  };

  # hardware.opengl.extraPackages =
  #   [
  #     ((pkgs.mesa.overrideAttrs (old: {
  #       src = pkgs.fetchFromGitLab {
  #         owner = "panfork";
  #         repo = "mesa";
  #         rev = "120202c675749c5ef81ae4c8cdc30019b4de08f4";
  #         sha256 = "sha256-4eZHMiYS+sRDHNBtLZTA8ELZnLns7yT3USU5YQswxQ0=";
  #       };
  #       # postPatch = ''
  #       #   cp src/panfrost/base/pan_base.h src/panfrost/lib/
  #       # '';
  #     })).override
  #       ({
  #         galliumDrivers = [ "swrast" "panfrost" ];
  #         vulkanDrivers = [ "swrast" ];
  #         # enableGalliumNine = false;
  #       }))
  #   ];

  nixpkgs.overlays = [
    # (self: super: {
    #   mesa = (super.mesa.overrideAttrs (old: {
    #     src = super.fetchFromGitLab {
    #       owner = "panfork";
    #       repo = "mesa";
    #       rev = "120202c675749c5ef81ae4c8cdc30019b4de08f4";
    #       sha256 = "sha256-4eZHMiYS+sRDHNBtLZTA8ELZnLns7yT3USU5YQswxQ0=";
    #     };
    #     # postPatch = ''
    #     #   cp src/panfrost/base/pan_base.h src/panfrost/lib/
    #     # '';
    #   })).override
    #     ({
    #       galliumDrivers = [ "swrast" "panfrost" ];
    #       vulkanDrivers = [ "swrast" ];
    #       # enableGalliumNine = false;
    #     });

    #   rockchip-mpp = super.callPackage ./mpp.nix { };

    #   ffmpeg_5 = (super.ffmpeg_5.overrideAttrs
    #     (old: {
    #       src = pkgs.fetchFromGitHub
    #         {
    #           owner = "JeffyCN";
    #           repo = "FFmpeg";
    #           rev = "master";
    #           sha256 = "sha256-LEP8pTo9u3woQxPlQzbLgezxD6EdLqfW6nrMQgP8dw0=";
    #         };
    #       buildInputs = old.buildInputs ++ [ self.rockchip-mpp ];
    #       configureFlags = old.configureFlags ++ [ "--enable-rkmpp" ];
    #     })).override ({
    #     withV4l2M2m = false;
    #     withVaapi = false;
    #     withVdpau = false;
    #   });
    # })
  ];

  # hardware.firmware = [
  #   (pkgs.stdenv.mkDerivation {
  #     pname = "libmali-fw";
  #     version = "dirty";
  #     src = ./mali_csffw.bin;
  #     buildCommand = ''
  #       install -D $src $out/lib/firmware/mali_csffw.bin
  #     '';
  #   })
  # ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        JustWorksRepairing = "always";
        FastConnectable = "true";
      };
      GATT = {
        AutoEnable = true;
      };
    };
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.initrd.availableKernelModules = lib.mkForce [ "usbhid" "md_mod" "raid0" "raid1" "raid10" "raid456" "ext2" "ext4" "sd_mod" "sr_mod" "mmc_block" "uhci_hcd" "ehci_hcd" "ehci_pci" "ohci_hcd" "ohci_pci" "xhci_hcd" "xhci_pci" "usbhid" "hid_generic" "hid_lenovo" "hid_apple" "hid_roccat" "hid_logitech_hidpp" "hid_logitech_dj" "hid_microsoft" "hid_cherry" ];

  system.stateVersion = lib.traceSeq config.boot.initrd.availableKernelModules "23.05";

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOTFS";
    fsType = "ext4";
  };

  swapDevices = [ ];

  networking = {
    hostName = "rock5b";
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

}
