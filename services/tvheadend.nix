{ options, config, lib, pkgs, ... }:

{

  boot.kernelPatches = [
    {
      # Disable regular kernel media modules since dependencies will
      # collide with other v4l2 from tbs modules
      name = "disable media";
      patch = null;
      extraConfig = ''
        MEDIA_SUPPORT n
        STAGING n
        PCI n
        WLAN n
        BT n
        DRM n
        SOUND n
        FS_XFS n
        FS_UDF n
        FS_UBIFS n
      '';
    }
    {
      # FRAME_VECTOR is needed by videobuf2
      # but wont get selected since we disabled above
      # reenable it manually
      name = "frame vector";
      patch = ./frame-vector.patch;
      extraConfig = ''
        FRAME_VECTOR y
      '';
    }
  ];

  hardware.firmware = [ pkgs.libreelec-dvb-firmware ];

  boot.kernelPackages = lib.mkOverride 1 pkgs.linuxPackages_allwinner;
  boot.extraModulePackages = [
    (config.boot.kernelPackages.tbs.overrideAttrs (old:
      let
        # fetchFromGitHub does unpack differently from niv ?
        media = pkgs.fetchFromGitHub { inherit (pkgs.sources.linux_media) repo owner rev sha256; name = "linux_media"; };
        build = pkgs.fetchFromGitHub { inherit (pkgs.sources.media_build) repo owner rev sha256; name = "media_build"; };
        media_patched = pkgs.runCommandNoCC "linux_media" { } ''
          cp -r ${media} linux_media
          chmod -R +w linux_media
          cd linux_media
          patch -p1 < ${../packages/patches/linux-tbs.patch}
          cd ..
          mv linux_media $out
        '';
      in
      {
        name = "tbs-2020.01.01";
        srcs = [ media_patched build ];
        sourceRoot = "media_build";

        preConfigure = let
          disableModule = module: ''
            sed -i "/DVB_SAA716X_FF/a disable_config('${module}');" v4l/scripts/make_kconfig.pl
          '';
        in ''
          # dont need
          sed -i "/DVB_SAA716X_FF/a disable_config('MEDIA_PCI_SUPPORT');" v4l/scripts/make_kconfig.pl

          # fails build (perhaps only VIN)
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_RCAR_DRIF');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_RCAR_CSI2');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_RCAR_VIN');" v4l/scripts/make_kconfig.pl

          # broken
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_TDA1997X');" v4l/scripts/make_kconfig.pl

          # nothing good comes of mediatek
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MEDIATEK_VPU');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MEDIATEK_VCODEC');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MEDIATEK_MDP');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('IR_MTK');" v4l/scripts/make_kconfig.pl

          # missing includes
          sed -i "/ti_wilink_st/a TARFILES += include/linux/interconnect.h" linux/Makefile

          # meson-canvas.h fails
          sed -i "/DVB_SAA716X_FF/a disable_config('IR_MESON');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MESON_G12A_AO_CEC');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_MESON_AO_CEC');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_QCOM_VENUS');" v4l/scripts/make_kconfig.pl

          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_SUN4I_CSI');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_SUN6I_CSI');" v4l/scripts/make_kconfig.pl

          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_CODA');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_IMX_VDOA');" v4l/scripts/make_kconfig.pl

          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_SAA7146');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_SAA7146_VV');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_TC358743');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_OV9650');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_ADV7511');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_ADV7842');" v4l/scripts/make_kconfig.pl
          sed -i "/DVB_SAA716X_FF/a disable_config('VIDEO_ADV7604');" v4l/scripts/make_kconfig.pl

          make dir DIR=../${media.name}

          # make module in parallel
          sed -i "/MYCFLAGS :=/s/.*/ MYCFLAGS := -j$NIX_BUILD_CORES/" v4l/Makefile
        '';
      }))
  ];

  services.tvheadend.enable = true;
  networking.firewall.allowedTCPPorts = [ 9981 9982 ];
}
