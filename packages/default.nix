{ pkgs ? import <nixpkgs> { }, ... }:

with pkgs;

rec {

  sources = (import ../nix/sources.nix);

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

  blind-control = callPackage ./blind-control { };
  dtv-scan-tables = callPackage ./dtv-scan-tables { };
  meson-firmware = callPackage ./meson-firmware { };
  natures_prophet = callPackage ./natures_prophet { };

  python3 = pkgs.python3.override {
    packageOverrides = self: super_:
      (pkgs.python3.pkgs.callPackage ./python-libraries { });
  };
  python3Packages = python3.pkgs;

  entking = callPackage ./entking { };
  miflora-mqtt-daemon = callPackage ./miflora-mqtt-daemon { };

  am43-ctrl = (callPackage ./am43-ctrl/override.nix { }).package;

  libva-v4l2-request = (callPackage ./libva-v4l2-request { });
  hsphfpd = (callPackage ./hsphfpd { });

}
