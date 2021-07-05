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
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns { };

  ethminer = callPackage ./ethminer { };
  phoenix-miner = callPackage ./phoenix-miner { };
  graph-node = callPackage ./graph-node { };
  uniswap = (callPackage sources.uniswap-data { }).overrideAttrs(o: {
      cargoSha256 = "1qg7b4jw0f4zab2jfl8yljcypmiggy81sh2k37wa1wv2pfn9p6yh";
  });
  besu = callPackage ./besu { };

  dtv-scan-tables = callPackage ./dtv-scan-tables { };
  meson-firmware = callPackage ./meson-firmware { };
  footbot = callPackage ./footbot { };

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

  rtl8723bs_bt = (callPackage ./rtl8723bs_bt { });
  font-5x5 = (callPackage ./5x5-font { });

  weather = (callPackage ./weather { });
  farmbot = (callPackage /mnt/Home/src/farmbot { });
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

  lazylibrarian = (callPackage ./lazylibrarian { });
  go-bsc = (callPackage ./bsc { });

}
