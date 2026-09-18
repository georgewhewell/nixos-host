{
  lib,
  stdenv,
  erofs-utils,
  kernel,
  initrd,
  dtb,
  dtbo ? null,
  cmdline,
  name ? "nanokvm-kexec-payload",
}: let
  cmdlineArg = lib.escapeShellArg cmdline;
  mkfsArgs = lib.escapeShellArgs [
    "-T"
    "0"
    "--all-root"
  ];
in
  stdenv.mkDerivation {
    inherit name;

    nativeBuildInputs = [erofs-utils];

    buildCommand = ''
      mkdir payload
      cp ${kernel} payload/Image
      cp ${initrd} payload/initrd
      cp ${dtb} payload/dtb
      ${lib.optionalString (dtbo != null) "cp ${dtbo} payload/overlay.dtbo"}
      printf '%s\n' ${cmdlineArg} > payload/cmdline

      mkfs.erofs ${mkfsArgs} "$out" payload
    '';
  }
