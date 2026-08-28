# LVGL status dashboard for the claw's PicoClaw ST7789 (240x240, SPI1).
#
# Not registered in ../default.nix on purpose: this builds with the board's
# cross riscv64 pkgs set, callPackage'd from machines/riscv/claw/default.nix.
# LVGL is compiled from a pinned source tarball with the local lv_conf.h —
# the standard LVGL integration, since usable settings are per-project.
{ lib, stdenv, fetchFromGitHub }:

let
  lvgl = fetchFromGitHub {
    owner = "lvgl";
    repo = "lvgl";
    rev = "v9.3.0";
    hash = "sha256-q3QGtZBusgSO+Vs6fxtUtrDiuzkACE3JtY3E+Nng+5k=";
  };
in
stdenv.mkDerivation {
  pname = "claw-lcd-status";
  version = "0.1.0";

  # Ships claw-lcd-status.c and lv_conf.h; LV_CONF_INCLUDE_SIMPLE makes
  # lvgl.h pick up lv_conf.h from the include path.
  src = ./.;

  buildPhase = ''
    runHook preBuild

    flags="-O2 -DLV_CONF_INCLUDE_SIMPLE -I. -I${lvgl} -I${lvgl}/src"
    # All of lvgl/src is guarded by lv_conf feature macros, so disabled
    # subsystems compile to empty objects. No duplicate basenames in v9.3
    # (verified), so -c into the cwd is safe. C sources only.
    $CC $flags -c claw-lcd-status.c
    find ${lvgl}/src -name '*.c' | xargs -n 50 $CC $flags -c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    $CC -O2 -o $out/bin/claw-lcd-status ./*.o -lm
    runHook postInstall
  '';

  meta = {
    description = "LVGL status dashboard for the PicoClaw ST7789 SPI LCD";
    mainProgram = "claw-lcd-status";
    platforms = lib.platforms.linux;
  };
}
