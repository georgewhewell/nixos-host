{ config, lib, pkgs, ... }:

{
  imports = [
    ../common-arm.nix
  ];

  sconfig = {
    profile = "server";
  };

  hardware.cpu.intel.updateMicrocode = lib.mkForce false;

  nixpkgs.overlays = [
    (self: super: {

      /* should be able to set this null but preBuild unconditionally uses it  */
      wpa_supplicant = super.wpa_supplicant.overrideAttrs (o: {
        buildInputs = with self; [ openssl libnl dbus readline ];
        preBuild = ''
          for manpage in wpa_supplicant/doc/docbook/wpa_supplicant.conf* ; do
            substituteInPlace "$manpage" --replace /usr/share/doc $out/share/doc
          done
          cd wpa_supplicant
          cp -v defconfig .config
          echo "$extraConfig" >> .config
          sed -i '/CONFIG_PCSC/d' .config
          sed -i '/CONFIG_EAP_SIM/d' .config
          sed -i '/CONFIG_EAP_AKA/d' .config
          sed -i '/CONFIG_EAP_AKA_PRIME/d' .config
          cat -n .config
          substituteInPlace Makefile --replace /usr/local $out
          export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE \
            -I$(echo "${lib.getDev self.libnl}"/include/libnl*/)"
        '';
      });

      /* gtk-doc = null; */
      rfcomm = self.bluez.overrideAttrs (
        old: {
          name = "rfcomm";
          configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-deprecated" ];
          makeFlags = [ "tools/rfcomm" ];
          doCheck = false;
          outputs = [ "out" ];
          installPhase = ''
            install -D tools/rfcomm $out/bin/rfcomm
          '';
        }
      );
    })
  ];

  # takes ages
  security.polkit.enable = lib.mkForce false;
  services.udisks2.enable = lib.mkForce false;

  boot.kernelPatches = [
    {
      name = "nanopi-air";
      patch = ../../packages/patches/nanopi-air-nand-wifi.patch;
    }
    {
      name = "otg-stuff";
      patch = null;
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
