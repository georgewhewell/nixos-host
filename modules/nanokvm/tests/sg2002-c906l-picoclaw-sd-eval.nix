{ pkgs, config }:

let
  requiredInitrdModules = [
    "sg2002-c906l-control"
    "sg2002-c906l-remoteproc"
    "sg2002-c906l-wifi-power"
    "sg2002-c906l-framebuffer"
  ];
in
assert config.sg2002.auxCore.enable;
assert config.sg2002.auxCore.peripherals == [ "picoclawLcd" ];
assert config.sg2002.auxCore.fdt.boardProfile == "picoclaw-c906l-lcd";
assert config.system.build.fip.c906lContract.profileName == "picoclaw-lcd";
assert config.system.build.sdImage != null;
assert config.sg2002.watchdogKeeper.initrd.enable;
assert config.sg2002.watchdogKeeper.stage2.enable;
assert config.sg2002.watchdogKeeper.healthHost == null;
assert config.sg2002.wifi.enable;
assert config.sg2002.wifi.wpaConfRuntimePath
  == "/etc/wpa_supplicant/wpa_supplicant-wlan0.conf";
assert !config.sg2002.usbGadget.console.enable;
assert !builtins.elem "console=ttyGS0,115200" config.boot.kernelParams;
assert config.sg2002.authorizedKeys == [];
assert config.services.openssh.enable;
assert config.services.openssh.settings.PermitRootLogin == "yes";
assert config.services.openssh.settings.PasswordAuthentication;
assert !config.services.openssh.settings.KbdInteractiveAuthentication;
assert config.users.mutableUsers;
assert config.users.users.root.initialPassword == null;
assert pkgs.lib.hasPrefix "$6$" config.users.users.root.hashedPassword;
assert pkgs.lib.all
  (module: builtins.elem module config.sg2002.initrd.availableKernelModules)
  requiredInitrdModules;
assert pkgs.lib.all
  (module: builtins.elem module config.sg2002.initrd.kernelModules)
  requiredInitrdModules;
pkgs.runCommand "sg2002-c906l-picoclaw-sd-module-eval" { } ''
  touch "$out"
''
