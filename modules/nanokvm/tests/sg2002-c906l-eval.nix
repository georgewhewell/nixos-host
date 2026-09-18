{ pkgs
, lib
, config
, artifactArgs
, firmwareMismatch
, fdtMismatch
, duplicatePeripherals
}:

let
  expectedPeripherals = [ "timer4" "timer5" "timer6" "timer7" ];
  expectedProfile = "all-timers";
  packageNames = map lib.getName config.environment.systemPackages;
in
assert config.sg2002.auxCore.enable;
assert config.sg2002.auxCore.peripherals == expectedPeripherals;
assert config.sg2002.auxCore.firmware.enabledPeripherals == expectedPeripherals;
assert config.sg2002.auxCore.firmware.profileName == expectedProfile;
assert config.sg2002.auxCore.fdt.profileName == expectedProfile;
assert config.system.build.fip.c906lContract.profileName == expectedProfile;
assert config.system.build.fipFastboot.c906lContract.profileName == expectedProfile;
assert config.sg2002.auxCore.firmware.contractSha256
  == config.sg2002.auxCore.fdt.contractSha256;
assert config.sg2002.auxCore.firmware.contractSha256
  == config.system.build.fip.c906lContract.contractSha256;
assert config.sg2002.watchdogKeeper.initrd.enable;
assert config.sg2002.watchdogKeeper.stage2.enable;
assert config.sg2002.watchdogKeeper.healthHost == "10.55.0.2";
assert !config.sg2002.usbGadget.console.enable;
assert config.sg2002.usbGadget.network.enable;
assert config.nanokvm.usbControl.initrd.enable;
assert config.nanokvm.usbControl.stage2.enable;
assert builtins.hasAttr "usb-debug-shell" config.boot.initrd.systemd.services;
assert builtins.hasAttr "usb-debug-shell" config.systemd.services;
assert artifactArgs.usbConsole == false;
assert (artifactArgs.uartConsole or "ttyS0") == "ttyS0";
assert !config.services.nanokvm.enable;
assert !config.services.openssh.enable;
assert builtins.length packageNames == 4;
assert builtins.elem "sg2002-c906l-ctl-all-timers" packageNames;
assert !firmwareMismatch.success;
assert !fdtMismatch.success;
assert !duplicatePeripherals.success;
pkgs.runCommand "sg2002-c906l-module-eval" { } ''
  touch "$out"
''
