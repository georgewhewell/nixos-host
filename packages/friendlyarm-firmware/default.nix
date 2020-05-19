{ stdenv, fetchurl, fetchFromGitHub }:

stdenv.mkDerivation rec {
  name = "friendlyarm-firmware";

  src = fetchFromGitHub {
    owner = "friendlyarm";
    repo = "sd-fuse_h3";
    rev = "ead97d7fa8f7c2f65adff1e0827ce1009066fcd5";
    sha256 = "1xgbikmplg57kxvggn07fcqr4j5bwr58n0fyb756j1bx640p8b67";
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    ls -la .
    env
    mkdir -p $out/lib/firmware
    cp -rv prebuilt/wifi_firmware/ap6xxx/lib/firmware/ap6212 $out/lib/firmware/brcm
    cp -rv $out/lib/firmware/brcm/fw_bcm43438a0.bin $out/lib/firmware/brcm/bcm43430-sdio.bin
    cp -rv ${fetchurl {
      url = "https://raw.githubusercontent.com/friendlyarm/android_vendor_broadcom_nanopi2/nanopi2-lollipop-mr1/proprietary/nvram_ap6212a.txt";
      sha256 = "1rhsjknicpybrvd505vdc14p4n0x4clgjk0qxdf7kvqn74m7m5sz";
    }} $out/lib/firmware/brcm/brcmfmac43430-sdio.friendlyarm,nanopi-neo-air.txt
  '';

  meta = {
    description = "friendlyarm firmware files for AP6212";
    maintainers = [ stdenv.lib.maintainers.georgewhewell ];
  };

}
