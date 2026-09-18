{ pkgs, config, artifactArgs, picoclawFdtMismatch }:

let
  packageNames = map pkgs.lib.getName config.environment.systemPackages;
  extraModuleNames = map pkgs.lib.getName config.boot.extraModulePackages;
  initrdStorePaths =
    map (entry: toString entry.source) config.boot.initrd.systemd.storePaths;
  initrdNbdPackages = builtins.filter
    (path: pkgs.lib.hasInfix "-nbd-client-minimal-" path)
    initrdStorePaths;
  nbdClient = "${builtins.head initrdNbdPackages}/bin/nbd-client";
  rootNbdScript =
    config.boot.initrd.systemd.services.nanokvm-root-nbd.serviceConfig.ExecStart;
in
assert config.sg2002.auxCore.enable;
assert config.sg2002.auxCore.peripherals == [ "picoclawLcd" ];
assert config.sg2002.auxCore.firmware.profileName == "picoclaw-lcd";
assert config.sg2002.auxCore.fdt.profileName == "picoclaw-lcd";
assert config.sg2002.auxCore.fdt.boardProfile == "picoclaw-c906l-lcd";
assert config.system.build.fip.c906lContract.profileName == "picoclaw-lcd";
assert config.system.build.fipFastboot.c906lContract.profileName == "picoclaw-lcd";
assert config.sg2002.watchdogKeeper.initrd.enable;
assert config.sg2002.watchdogKeeper.stage2.enable;
assert config.sg2002.watchdogKeeper.healthHost == "10.55.0.2";
assert !config.sg2002.usbGadget.console.enable;
assert config.sg2002.usbGadget.network.enable;
assert config.nanokvm.usbControl.initrd.enable;
assert config.nanokvm.usbControl.stage2.enable;
assert artifactArgs.usbConsole == false;
assert artifactArgs.extraBootargs == [
  "systemd.getty_auto=no"
  "udev.children_max=2"
];
assert config.sg2002.wifi.enable;
assert config.sg2002.auxCore.fdt.wifiPowerProvider == "c906l-regulator";
assert !config.services.nanokvm.enable;
assert !config.services.openssh.enable;
assert config.services.userborn.static;
assert !config.zramSwap.enable;
assert !config.nanokvm.usbControl.kexec.enable;
assert builtins.length initrdNbdPackages == 1;
assert !config.systemd.oomd.enable;
assert !config.systemd.network.wait-online.enable;
assert builtins.elem "systemd.getty_auto=no" config.boot.kernelParams;
assert builtins.elem "udev.children_max=2" config.boot.kernelParams;
assert builtins.length packageNames == 5;
assert builtins.elem "sg2002-c906l-ctl-picoclaw-lcd" packageNames;
assert builtins.elem "sg2002-c906l-drm-test" packageNames;
assert builtins.elem "sg2002-c906l-control" extraModuleNames;
assert builtins.elem "sg2002-c906l-remoteproc" extraModuleNames;
assert builtins.elem "sg2002-c906l-framebuffer" extraModuleNames;
assert builtins.elem "sg2002-c906l-wifi-power" extraModuleNames;
assert builtins.elem "sg2002-c906l-wifi-power" config.boot.kernelModules;
assert builtins.elem "sg2002-c906l-framebuffer" config.boot.kernelModules;
assert !picoclawFdtMismatch.success;
pkgs.runCommand "sg2002-c906l-picoclaw-module-eval" { } ''
  grep -F '${nbdClient} -c /dev/nbd0' ${rootNbdScript} >/dev/null
  grep -F 'exec ${nbdClient} -n --systemd-mark' ${rootNbdScript} >/dev/null
  if grep -F 'if nbd-client ' ${rootNbdScript} >/dev/null \
      || grep -F 'exec nbd-client ' ${rootNbdScript} >/dev/null; then
    echo "root NBD helper retains a PATH-resolved nbd-client fallback" >&2
    exit 1
  fi
  touch "$out"
''
