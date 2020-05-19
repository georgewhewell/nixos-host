{ pkgs ? import <nixpkgs> { } }:

with pkgs;
with stdenv.lib;

stdenv.mkDerivation rec {
  name = "broadcom-bluetooth-${version}";
  version = "unstable";

  src = ./broadcom-bluetooth;

  buildInputs = [ bluez ];

  installPhase = ''
    mkdir -p $out/bin
    cp brcm_patchram_plus brcm_patchram_plus_h5 brcm_patchram_plus_usb $out/bin
  '';

}
