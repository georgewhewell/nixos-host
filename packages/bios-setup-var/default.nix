{
  lib,
  stdenvNoCC,
  python3,
  uefitool,
  ifrextractor-rs,
  makeWrapper,
  e2fsprogs,
}:
stdenvNoCC.mkDerivation {
  pname = "bios-setup-var";
  version = "0.3.3";

  src = ./.;

  nativeBuildInputs = [makeWrapper];

  installPhase = ''
    runHook preInstall

    install -Dm755 setup_var.py $out/bin/bios-setup-var
    install -Dm444 faex9-1.04-known.json \
      $out/share/bios-setup-var/faex9-1.04-known.json
    patchShebangs $out/bin/bios-setup-var

    # uefiextract + ifrextractor are the extraction backends; chattr (e2fsprogs)
    # clears the efivarfs immutable flag before a write.
    wrapProgram $out/bin/bios-setup-var \
      --set UEFIEXTRACT ${uefitool}/bin/uefiextract \
      --set IFREXTRACTOR ${ifrextractor-rs}/bin/ifrextractor \
      --prefix PATH : ${lib.makeBinPath [python3 e2fsprogs]}

    runHook postInstall
  '';

  meta = {
    description = "Map BIOS Setup questions to EFI variable offsets and get/set them live";
    longDescription = ''
      Extracts the IFR question map from a BIOS dump (via uefiextract +
      ifrextractor) and uses it to read or write opaque AMI/AMD Setup EFI
      variables on a running machine, making BIOS-menu-only settings such as
      PCIe lane bifurcation scriptable. Writes verify the target offset holds a
      legal value before touching it and back the variable up first.
    '';
    mainProgram = "bios-setup-var";
    platforms = lib.platforms.linux;
  };
}
