{ super ? import <nixpkgs> { }, ... }:

with super;

rec {
  openelec-fw-dvb = callPackage ./openelec-fw-dvb.nix { };
  libreelec-dvb-firmware = callPackage ./libreelec-dvb-firmware { };
  /*
  BCM20702A1 = callPackage ./BCM20702A1.nix { };
  couchpotato = callPackage ./couchpotato.nix { };
  jackett = callPackage ./jackett.nix { };
  kubernetes_15 = callPackage ./kubernetes.nix { };
  radarr = callPackage ./radarr.nix { };
  headphones = callPackage ./headphones.nix { };
  thin-provisioning-tools = callPackage ./thin-provisioning-tools.nix { };
  clover = callPackage ./clover { };
  cni = callPackage ./cni.nix { };
  esp-open-sdk = callPackage ./esp-open-sdk.nix { };
  xtensa-esp32-elf = callPackage ./xtensa-esp32-elf { };
  micro-ecc = callPackage ./micro-ecc { };
  esp-idf = callPackage ./esp-idf { inherit micro-ecc; };
  als-yoga = callPackage ./als-yoga { inherit (python.pkgs) buildPythonApplication; };
  sentry = python36Packages.callPackage ./sentry { };
  gemini-flashtool = callPackage ./gemini-flashtool { };
  kmmscube = callPackage ./kmscube { };
  deCONZ = callPackage ./deCONZ { };

  python3 = super.python3.override {
    packageOverrides = python-self: python-super: {
      pydeconz = python-super.callPackage ./pydeconz { };
    };
  }; */
  deCONZ = callPackage ./deCONZ { };
  prometheus-ipmi-exporter = callPackage ./ipmi-exporter.nix { };
  xradio = callPackage ./xradio { };
  armbian-firmware = callPackage ./armbian-firmware { };
  gonbdserver = callPackage ./gonbdserver { };
  sunxi-dt-overlays = callPackage ./sunxi-DT-overlays { };

  linux-megous = callPackage ./linux-megous {};
  linuxPackages_megous = linuxPackagesFor linux-megous;

  linux-ayufan = callPackage ./linux-ayufan {};
  linuxPackages_ayufan = linuxPackagesFor linux-ayufan;

  linux-ayufan-4_4 = callPackage ./linux-ayufan-4_4.nix {};
  linuxPackages_ayufan-4_4 = linuxPackagesFor linux-ayufan-4_4;

  boot-scripts = callPackage ./uboot {};

  blind-control = callPackage ./blind-control { };
  dtv-scan-tables = callPackage ./dtv-scan-tables { };
  meson-firmware = callPackage ./meson-firmware { };

  inherit (super) pkgsCross;

}
