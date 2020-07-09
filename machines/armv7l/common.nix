{ config, lib, pkgs, ... }:

{
  imports = [
    ../common-arm.nix
  ];

  nixpkgs.overlays = [
    (self: super: {
      bluez = (
        let
          python3_ = super.python3.override {
            packageOverrides = python-self: python-super: {
              pygobject3 = python-super.pygobject3.overrideAttrs (oldAttrs: {
                propagatedBuildInputs = [ ];
                PYGOBJECT_WITHOUT_PYCAIRO = 1;
                mesonFlags = oldAttrs.mesonFlags ++ [
                  "-Dpycairo=false"
                ];
              });
            };
          };
        in
        (super.bluez.override ({
          python3 = python3_;
          libical = super.libical.overrideAttrs (o: {
            doInstallCheck = false;
          });
        })).overrideAttrs (o: {
          patches = [
            (super.fetchurl {
              url = "https://raw.githubusercontent.com/OpenELEC/OpenELEC.tv/6b9e7aaba7b3f1e7b69c8deb1558ef652dd5b82d/packages/network/bluez/patches/bluez-07-broadcom-dont-set-speed-before-loading.patch";
              sha256 = "1qgihk1vbwn5msk9rj7xwybcn0kwd0pzq7sh2vljgkng5ixxxff3";
            })
          ];
        })
      );
    })
  ];

  # takes ages
  security.polkit.enable = lib.mkForce false;
  services.udisks2.enable = lib.mkForce false;
  services.mingetty.autologinUser = lib.mkForce "grw";

  boot.kernelPatches = [
    {
      name = "nanopi-air";
      patch = ../../packages/patches/nanopi-air-nand-wifi.patch;
    }
    {
      name = "nanopi-duo";
      patch = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/armbian/build/master/patch/kernel/sunxi-dev/board-h2plus-nanopi-duo-add-device.patch";
        sha256 = "1vksyr3icjf0j53fmsghbj5bl1ip25v4kh0s7lm3s91mdk5kk86m";
      };
      extraConfig = ''
        USB_DWC2 m
        USB_OTG y
        USB_WDM m
        U_SERIAL_CONSOLE y
        USB_SNP_CORE m
        USB_SNP_UDC_PLAT m
        USB_F_ACM m
        USB_F_SS_LB m
        USB_U_SERIAL m
        USB_U_AUDIO m
        USB_F_SERIAL m
        USB_F_OBEX m
        USB_F_NCM m
        USB_F_EEM m
        USB_F_MASS_STORAGE m
        USB_F_FS m
        USB_F_UAC1 m
        USB_F_UAC2 m
        USB_F_UVC m
        USB_F_MIDI m
        USB_F_HID m
        USB_F_PRINTER m
        USB_MUSB_GADGET m
        USB_GADGET y
        USB_CONFIGFS m
        USB_CONFIGFS_SERIAL y
        USB_CONFIGFS_ACM y
        USB_CONFIGFS_OBEX y
        USB_CONFIGFS_NCM y
        USB_CONFIGFS_ECM y
        USB_CONFIGFS_ECM_SUBSET y
        USB_CONFIGFS_RNDIS y
        USB_CONFIGFS_EEM y
        USB_CONFIGFS_MASS_STORAGE y
        USB_CONFIGFS_F_LB_SS y
        USB_CONFIGFS_F_FS y
        USB_CONFIGFS_F_UAC1 y
        USB_CONFIGFS_F_UAC1_LEGACY y
        USB_CONFIGFS_F_UAC2 y
        USB_CONFIGFS_F_MIDI y
        USB_CONFIGFS_F_HID y
        USB_CONFIGFS_F_UVC y
        USB_ETH_EEM y
        USB_G_NCM m
        USB_GADGETFS m
        USB_FUNCTIONFS m
        USB_FUNCTIONFS_ETH y
        USB_FUNCTIONFS_RNDIS y
        USB_MASS_STORAGE m
        USB_G_SERIAL m
        USB_MIDI_GADGET m
        USB_G_PRINTER m
        USB_CDC_COMPOSITE m
        USB_G_ACM_MS m
        USB_G_MULTI m
        USB_G_MULTI_RNDIS y
        USB_G_MULTI_CDC y
      '';
    }
  ];

}
