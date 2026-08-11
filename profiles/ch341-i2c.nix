{ config, lib, pkgs, ... }:

# Bench I2C/SMBus master over a CH341A USB dongle, for talking to devices that
# have no host-side bus of their own — the SMBus header on the Broadcom PEX
# switch boards being the reason this exists.
#
# Deliberately unconditional on every host that imports it. The dongle is a
# USB stick that moves between benches, and keying it on a per-host inventory
# flag is exactly how systemd.services.pex-acs-clear silently stopped running
# everywhere when the PEX board changed chassis. All of this is inert when
# nothing is plugged in.
{
  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ../packages/ch341-i2c-spi-gpio { })
  ];

  # Mainline's spi_ch341 and this package's ch341-core both bind USB
  # 1a86:5512 interface 0, and only one can win. spi_ch341 gets there first
  # via udev's modalias autoload, which leaves the dongle claimed by a driver
  # that exposes SPI and no I2C adapter. Blocking the alias hands the
  # interface to ch341-core, which registers the ch341-i2c and ch341-gpio
  # cells. This forfeits SPI on the CH341 — the point of the dongle here is
  # the I2C master, and flashrom-style SPI work is not what it is wired for.
  boot.blacklistedKernelModules = [ "spi_ch341" ];

  # i2c-dev supplies the /dev/i2c-N character devices that i2c-tools drives.
  # ch341-core is loaded eagerly so the adapter exists after a plug event even
  # though the blacklist above removed the autoload path that would find it.
  boot.kernelModules = [ "i2c-dev" "ch341-core" ];

  environment.systemPackages = [ pkgs.i2c-tools ];
}
