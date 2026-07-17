{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, dpkg
}:

stdenv.mkDerivation {
  pname = "mlnx-mft";
  version = "4.22.1-520";

  src = fetchurl {
    url = "https://linux.mellanox.com/public/repo/mlnx_ofed/latest-5.8/ubuntu20.04/amd64/mft_4.22.1-520_amd64.deb";
    hash = "sha256-M2JzNvrEzkF/CfJoccry/+27JnOUQcG07BemakrTrTs=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --extract "$src" source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/etc/mft" "$out/lib64" "$out/share"
    cp source/usr/bin/mlxlink_ext "$out/bin/mlxlink"
    cp source/usr/bin/mlxcables source/usr/bin/mlxcables_ext "$out/bin/"
    cp source/usr/bin/mlxreg source/usr/bin/mlxreg_ext "$out/bin/"
    install -Dm755 ${./mlx5-cable-eeprom-dump} \
      "$out/bin/mlx5-cable-eeprom-dump"
    substituteInPlace "$out/bin/mlx5-cable-eeprom-dump" \
      --replace-fail '@mlxreg@' "$out/bin/mlxreg"
    cp source/etc/mft/mft.conf "$out/etc/mft/mft.conf"
    mkdir -p "$out/lib64/mft/mtcr_plugins"
    cp source/usr/lib64/mft/mtcr_plugins/mcables.so \
      "$out/lib64/mft/mtcr_plugins/"
    cp -r source/usr/share/mft "$out/share/mft"
    substituteInPlace "$out/etc/mft/mft.conf" \
      --replace-fail 'mft_prefix_location=/usr' "mft_prefix_location=$out" \
      --replace-fail 'mft_lib_location=/usr/lib64' "mft_lib_location=$out/lib64"
    runHook postInstall
  '';

  meta = {
    description = "NVIDIA Firmware Tools mlxlink diagnostic utility";
    homepage = "https://network.nvidia.com/products/adapter-software/firmware-tools/";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "mlxlink";
  };
}
