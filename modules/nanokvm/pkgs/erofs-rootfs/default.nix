{
  lib,
  stdenv,
  erofs-utils,
  closureInfo,
  toplevel,
  compression ? null,
  mkfsExtraArgs ? [],
}:
let
  compressionArgs = lib.optionals (compression != null) [
    "-z"
    compression
  ];
  mkfsArgs = lib.escapeShellArgs (
    compressionArgs
    ++ mkfsExtraArgs
    ++ [
      "-T"
      "0"
      "--all-root"
    ]
  );
in
stdenv.mkDerivation {
  name = "nanokvm-erofs-rootfs";
  __structuredAttrs = true;

  unsafeDiscardReferences.out = true;

  nativeBuildInputs = [erofs-utils];

  buildCommand = ''
    closureInfo=${closureInfo {rootPaths = [toplevel];}}

    mkdir store
    while read -r p; do
      cp -a --reflink=auto "$p" store/
    done < "$closureInfo/store-paths"

    cp "$closureInfo/registration" store/nix-path-registration

    mkfs.erofs ${mkfsArgs} "$out" store
  '';
}
