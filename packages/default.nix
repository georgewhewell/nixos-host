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

  dtv-scan-tables = callPackage ./dtv-scan-tables { };
  meson-firmware = callPackage ./meson-firmware { };
  natures_prophet = callPackage ./natures_prophet { };

  python3 = pkgs.python3.override {
    packageOverrides = self: super_:
      (pkgs.python3.pkgs.callPackage ./python-libraries { });
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

  linux_allwinner = (import ./linux-allwinner { inherit linux_testing sources; });
  linuxPackages_allwinner = linuxPackagesFor (linux_allwinner);

  linux_amlogic = (import ./linux-amlogic { inherit linux_latest sources; });
  linuxPackages_amlogic = linuxPackagesFor (linux_amlogic);

  linux_meson_mx = (import ./linux-meson-mx { inherit linux_testing sources; });
  linuxPackages_meson_mx = linuxPackagesFor (linux_meson_mx);

}
