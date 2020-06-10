{ stdenv, libuuid, python2, iasl, callPackage, nasm, seabios, openssl, secureBoot ? false, targetArch ? "X64" }:
let
  edk2 = callPackage ./edk2-macboot.nix { };
  version = (builtins.parseDrvName edk2.name).version;
in
stdenv.mkDerivation (edk2.setup "OvmfPkg/OvmfPkg${targetArch}.dsc" {
  name = "OVMF-${version}";

  # TODO: properly include openssl for secureBoot
  buildInputs = [ nasm iasl ] ++ stdenv.lib.optionals (secureBoot == true) [ openssl ];
  enableParallelBuilding = true;

  hardeningDisable = [ "stackprotector" "pic" "fortify" ];

  unpackPhase = ''
    # $fd is overwritten during the build
    export OUTPUT_FD=$fd
    for file in \
      "${edk2.src}"/{UefiCpuPkg,MdeModulePkg,IntelFrameworkModulePkg,PcAtChipsetPkg,FatPkg,FatBinPkg,EdkShellBinPkg,MdePkg,ShellPkg,OptionRomPkg,IntelFrameworkPkg,SourceLevelDebugPkg,SecurityPkg,CryptoPkg};
    do
      ln -sv "$file" .
    done

    cp -r ${edk2.src}/OvmfPkg .
    chmod +w OvmfPkg/Csm/Csm16
    cp ${seabios}/Csm16.bin OvmfPkg/Csm/Csm16/Csm16.bin
  '';

  buildPhase = ''
    build -a X64 -t GCC5 -p OvmfPkg/OvmfPkgX64.dsc
  '';

  installPhase = ''
    mkdir $out
    cp $(find ./Build/ -name OVMF.fd) $out
  '';

  dontPatchELF = true;
  meta = {
    description = "Sample UEFI firmware for QEMU and KVM";
    homepage = http://sourceforge.net/apps/mediawiki/tianocore/index.php?title=OVMF;
    license = stdenv.lib.licenses.bsd2;
    platforms = [ "x86_64-linux" "i686-linux" ];
  };
}
)
