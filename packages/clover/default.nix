{ pkgs, ... }:

with pkgs;
let
  ovmf-image = callPackage ./X64-ovmf.nix { };
in
{
  libvirt-darwin = stdenv.mkDerivation {
    name = "libvirt-darwin";
    src = ./.;

    EFI_LOADER = "${ovmf-image}/OVMF.fd";
    QEMU_BIN = "/run/current-system/sw/bin/qemu-system-x86_64";

    installPhase = "
      mkdir $out
      envsubst < ElCapitan_vnc.xml > $out/manifest.xml
     ";

    buildInputs = [ gettext ];
    propogatedBuildInputs = [
      ovmf-image
    ];
  };
}
