{
  lib,
  stdenv,
  fetchurl,
  fetchpatch,
  pkg-config,
  glib,
  which,
  bison,
  linuxHeaders,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nbd-client-minimal";
  version = "3.25";

  src = fetchurl {
    url = "https://github.com/NetworkBlockDevice/nbd/releases/download/nbd-${finalAttrs.version}/nbd-${finalAttrs.version}.tar.xz";
    hash = "sha256-9cj9D8tXsckmWU0OV/NWQy7ghni+8dQNCI8IMPDL3Qo=";
  };

  patches = [
    (fetchpatch {
      url = "https://github.com/NetworkBlockDevice/nbd/commit/915444bc0b8a931d32dfb755542f4bd1d37f1449.patch";
      hash = "sha256-6z+c2cXhY92WPDqRO6AJ5BBf1N38yTgOE1foduIr5Dg=";
    })
    ./clear-sock-before-reconnect.patch
  ];

  nativeBuildInputs = [
    pkg-config
    which
    bison
  ];

  buildInputs = [
    glib
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    linuxHeaders
  ];

  configureFlags = [
    "--sysconfdir=/etc"
    "--without-gnutls"
    "--without-libnl"
    "--disable-manpages"
  ];

  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm755 nbd-client "$out/bin/nbd-client"
    runHook postInstall
  '';

  meta = {
    homepage = "https://nbd.sourceforge.io/";
    description = "Minimal NBD client for initrd use";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
})
