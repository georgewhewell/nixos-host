{ config, lib, pkgs, ... }:

{
  nixpkgs.overlays = [
    (self: super: {
      auto-rotate = pkgs.stdenv.mkDerivation {
        name = "auto-rotate";
        version = "auto-rotate";

        src = super.fetchFromGitHub {
          owner = "mrquincle";
          repo = "yoga-900-auto-rotate";
          rev = "master";
          sha256 = "0ibg4mxkdhf19pn7h4z9xjx6gh2i9r67869yz60bwzzfzybhyqj2";
        };
        buildInputs = with pkgs; [
          iio-sensor-proxy
          pkgconfig
          glib
          x11
          xorg.libXrandr
        ];
        buildPhase = ''
          make
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp auto-rotate $out/bin/
        '';
      };

      validity90 = pkgs.stdenv.mkDerivation {
        name = "validity90";
        version = "unstable";
        src = super.fetchFromGitHub {
          owner = "nmikhailov";
          repo = "Validity90";
          rev = "00ac6ab7f54b012a8a0627fb389bd62ebf14c4fb";
          sha256 = "04hdfp80ckwjljk5np358rx3vcfhf2fqvs9b7savsazrgm2p955l";
        };
        sourceRoot = "source/prototype/";
        buildInputs = with pkgs; [
          pkgconfig
          glib.dev
          gnutls
          libusb
          libgcrypt
          libpng
          nss
          openssl.dev
        ];
        installPhase = ''
          mkdir -p $out/bin
          cp prototype $out/bin/validity90
        '';
      };

      /*
      libfprint = super.libfprint.overrideAttrs (old: {
        src = super.fetchFromGitHub {
          owner = "nmikhailov";
          repo = "Validity90";
          rev = "00ac6ab7f54b012a8a0627fb389bd62ebf14c4fb";
          sha256 = "04hdfp80ckwjljk5np358rx3vcfhf2fqvs9b7savsazrgm2p955l";
        };
        sourceRoot = "source/libfprint/";
        buildInputs = with pkgs; [
          autoreconfHook
          pkgconfig
          libusb
          nss
          glib
          pixman
        ];
      });
      */
    })
  ];
}
