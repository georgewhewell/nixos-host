{ stdenv
, sources
}:

stdenv.mkDerivation rec {
  pname = "rtl8723bs_bt";
  version = sources.rtl8723bs_bt.rev;

  src = sources.rtl8723bs_bt;

  buildPhase = ''
    substituteInPlace hciattach_rtk.c \
      --replace "/lib/firmware/rtl_bt/" "/run/current-system/firmware/rtl_bt/"
    $CC -c hciattach_rtk.c
    $CC  -o rtk_hciattach hciattach.c hciattach_rtk.o
  '';

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/lib/firmware/rtl_bt
    install -D rtk_hciattach $out/bin/
    install -D rtlbt_config $out/lib/firmware/rtl_bt/
    install -D rtlbt_fw $out/lib/firmware/rtl_bt/
  '';

}
