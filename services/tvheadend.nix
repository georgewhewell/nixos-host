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

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_4_19;
  boot.extraModulePackages = [
    (config.boot.kernelPackages.tbs.overrideAttrs(old: let
      media = pkgs.fetchFromGitHub rec {
	name = repo;
	owner = "tbsdtv";
	repo = "linux_media";
	rev = "e71fb1797e3c89d90a5cb55523f50e5918276698";
	sha256 = "1zy700rkm7blq5jc273c4n7msbidyg20snsr9hpfrd4lrggpqwxg";
      };
      build = pkgs.fetchFromGitHub rec {
	name = repo;
	owner = "tbsdtv";
	repo = "media_build";
	rev = "ef3744c6108e781887ff3ed0ec930eba0ca8835f";
	sha256 = "0v53iyj9cpa15psi2y7r3lpqf2pahb858nx4qnbrlgaxfrqps4l0";
      };
    in {
	name = "tbs-2020.01.01";
	srcs = [ media build ];
	preConfigure = ''
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

	  make dir DIR=../${media.name}

	  # make module in parallel
	  sed -i "/MYCFLAGS :=/s/.*/ MYCFLAGS := -j$NIX_BUILD_CORES/" v4l/Makefile
	'';
    }))
  ];

  services.tvheadend.enable = true; 
  networking.firewall.allowedTCPPorts = [ 9981 9982 ];
}
