# VPP 26.06 is the first FD.io release used by the BlueField lab after the
# nixpkgs 26.02 package.  Keep this as a small package overlay so the lab's
# existing `pkgs.vpp.override { withDpdk = false; ... }` and cn913x tuning stay
# intact without changing the service module or the machine definition.
final: prev:
  {
    vpp = prev.vpp.overrideAttrs (old: rec {
      version = "26.06";
      src = prev.fetchFromGitHub {
        owner = "FDio";
        repo = "vpp";
        tag = "v${version}";
        hash = "sha256-pYqDa1PA4GX+sk3gNR87lhsyKSVsqIA3NeEWVQPvubM=";
      };

      # >=25.02 reads /etc/os-release while configuring the package.  The
      # nixpkgs derivation already supplies this substitution; repeat it here
      # because this overlay replaces the source and sourceRoot together.
      postPatch = ''
        patchShebangs scripts/
        substituteInPlace pkg/CMakeLists.txt \
          --replace-fail "/etc/os-release" "${final.writeText "vpp-os-release" "ID=nixos"}"
      '';
      preConfigure = ''
        echo "${version}-nixos" > scripts/.version
        ./scripts/version
      '';
      postConfigure = ''
        patchShebangs ../tools/
        patchShebangs ../vpp-api/
      '';
      sourceRoot = "${src.name}/src";
      # GCC 13/14 emits a few upstream warnings in the CNAT plugin; VPP's
      # build promotes them to errors even though they are not correctness
      # failures for this package.
      env.NIX_CFLAGS_COMPILE = "-Wno-array-bounds -Wno-error";
      meta = (old.meta or {}) // {
        homepage = "https://s3-docs.fd.io/vpp/${version}/";
        platforms = final.lib.platforms.linux;
      };
    });
  }
