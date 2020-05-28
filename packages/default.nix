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

  linux-ayufan = callPackage ./linux-ayufan {};
  linuxPackages_ayufan = linuxPackagesFor linux-ayufan;

  linux-ayufan-4_4 = callPackage ./linux-ayufan-4_4.nix {};
  linuxPackages_ayufan-4_4 = linuxPackagesFor linux-ayufan-4_4;

  boot-scripts = callPackage ./uboot {};

  blind-control = callPackage ./blind-control { };
  dtv-scan-tables = callPackage ./dtv-scan-tables { };
  meson-firmware = callPackage ./meson-firmware { };
  natures_prophet = callPackage ./natures_prophet { };


  python3 = super.python3.override {
    packageOverrides = self: super_:
      (super.python3.pkgs.callPackage ./python-libraries { });
  };
  python3Packages = python3.pkgs;

  entking = (self.callPackage ./entking { });
  miflora-mqtt-daemon = (self.callPackage ./miflora-mqtt-daemon { });

  am43-ctrl = (callPackage ./am43-ctrl/override.nix { }).package;

  libva-v4l2-request = (callPackage ./libva-v4l2-request { });
  
  inherit (super) pkgsCross;

}
