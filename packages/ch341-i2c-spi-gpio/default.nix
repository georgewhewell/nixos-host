{
  stdenv,
  lib,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

# Out-of-tree I2C/GPIO drivers for the WCH CH341 in its 0x5512 (SPI/I2C/GPIO)
# mode. Mainline carries only the SPI half as a standalone USB driver
# (CONFIG_SPI_CH341), so an unmodified kernel gives a CH341A dongle no I2C
# adapter at all.
#
# ch341-core is an MFD that claims USB 1a86:5512 and registers the "ch341-i2c"
# and "ch341-gpio" cells; there is deliberately no SPI cell. Upstream's
# spi-ch341.c is a separate, self-binding driver that is the ancestor of the
# in-tree one, so building it here would install a second spi-ch341.ko under
# the same module tree. Drop it: it collides by name, it duplicates a driver
# the kernel already has, and it competes with ch341-core for the same USB
# interface. Consumers blacklist the in-tree spi_ch341 instead — see
# profiles/ch341-i2c.nix.
stdenv.mkDerivation {
  pname = "ch341-i2c-spi-gpio";
  version = "unstable-2025-11-18";

  src = fetchFromGitHub {
    owner = "frank-zago";
    repo = "ch341-i2c-spi-gpio";
    rev = "1f052295f7ecdbc2a19fb53d99dd4cc1f8312c47";
    hash = "sha256-H6COzd19Tzp5rwi9JU2b6HDdtpINipK37DqEy1JSD8s=";
  };

  postPatch = ''
    substituteInPlace Makefile --replace-fail "obj-m += spi-ch341.o" ""
    rm spi-ch341.c
  '';

  hardeningDisable = ["pic"];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # The upstream Makefile only defaults KDIR; a command-line assignment wins
  # over its `?=`. KVERSION is `uname -r` on the *builder*, which is why every
  # path it feeds has to be overridden rather than inherited.
  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall
    for module in ch341-core i2c-ch341 gpio-ch341; do
      install -D "$module.ko" \
        "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/mfd/$module.ko"
    done
    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/frank-zago/ch341-i2c-spi-gpio";
    description = "CH341 USB-to-I2C/GPIO adapter drivers (0x5512 mode)";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
