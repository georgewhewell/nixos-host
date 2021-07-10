{ pkgs ? import <nixpkgs> { }, ... }:

with pkgs;

rec {

  sources = (import ../nix/sources.nix);
  secrets = (import ../secrets);

  openelec-fw-dvb = callPackage ./openelec-fw-dvb.nix { };
  libreelec-dvb-firmware = callPackage ./libreelec-dvb-firmware { };
  libdvbcsa = callPackage ./libdvbcsa { };
  deCONZ = callPackage ./deCONZ { };
  prometheus-ipmi-exporter = callPackage ./ipmi-exporter.nix { };
  xradio = callPackage ./xradio { };
  armbian-firmware = callPackage ./armbian-firmware { };
  friendlyarm-firmware = callPackage ./friendlyarm-firmware { };
  broadcom-bluetooth = callPackage ./brcm-patchram-plus { };

  gonbdserver = callPackage ./gonbdserver { };
  sunxi-dt-overlays = callPackage ./sunxi-DT-overlays { };
  dt-overlays = callPackage ./dt-overlays { };
  boot-scripts = callPackage ./uboot { };

  ethminer = callPackage ./ethminer { };

  dtv-scan-tables = callPackage ./dtv-scan-tables { };
  meson-firmware = callPackage ./meson-firmware { };
  footbot = callPackage ./footbot { };

  python3 = pkgs.python3.override {
    packageOverrides = self: super_: {
      dulwich = super_.dulwich.overrideAttrs(o: {
        doCheck = false;
        doInstallCheck = false;
      });
      jaraco_collections = super_.jaraco_collections.overrideAttrs(o: {
        postInstall = ''
          find $out -name '*.pyc' -exec rm -rf {} \;
        '';
      });
      jaraco_functools = super_.jaraco_functools.overrideAttrs(o: {
        postInstall = ''
          find $out -name '*.pyc' -exec rm -rf {} \;
        '';
      });
      jaraco_classes = super_.jaraco_classes.overrideAttrs(o: {
        postInstall = ''
          find $out -name '*.pyc' -exec rm -rf {} \;
        '';
      });
      jaraco_text = super_.jaraco_text.overrideAttrs(o: {
        postInstall = ''
          find $out -name '*.pyc' -exec rm -rf {} \;
        '';
      });
      pytest-testmon = super_.pytest-testmon.overrideAttrs(o: {
        doCheck = false;
        doInstallCheck = false;
        propagatedBuildInputs = [ super_.pytest super_.coverage ];
      });
    } // (pkgs.python3.pkgs.callPackage ./python-libraries { });
  };
  python3Packages = python3.pkgs;

  python2 = pkgs.python2.override {
    packageOverrides = self: super_:
      (pkgs.python2.pkgs.callPackage ./python-libraries { });
  };
  python2Packages = python2.pkgs;

  entking = callPackage ./entking { };
  miflora-mqtt-daemon = callPackage ./miflora-mqtt-daemon { };

  am43-ctrl = (callPackage ./am43-ctrl/override.nix { }).package;

  libva-v4l2-request = (callPackage ./libva-v4l2-request { });
  hsphfpd = (callPackage ./hsphfpd { });
  radeon-profile-daemon = libsForQt5.callPackage ./radeon-profile-daemon { };

  rtl8723bs_bt = (callPackage ./rtl8723bs_bt { });
  font-5x5 = (callPackage ./5x5-font { });

  weather = (callPackage ./weather { });
  farmbot = (callPackage ./farmbot { });
  sysinfo = (callPackage ./sysinfo { });

  vendor-reset = ./vendor-reset;

  i2c-ch341-usb = (callPackage ./i2c-ch341-usb {});

  linux_allwinner = (import ./linux-allwinner { inherit linux_testing sources; });
  linuxPackages_allwinner = linuxPackagesFor (linux_allwinner);

  linux_allwinner5_7 = (import ./linux-allwinner-5-7 { inherit linux_latest sources; });
  linuxPackages_allwinner_5_7 = linuxPackagesFor (linux_allwinner5_7);

  linux_amlogic = (import ./linux-amlogic { inherit linux_latest sources; });
  linuxPackages_amlogic = linuxPackagesFor (linux_amlogic);

  linux_meson_mx = (import ./linux-meson-mx { inherit linux_testing sources; });
  linuxPackages_meson_mx = linuxPackagesFor (linux_meson_mx);

}
