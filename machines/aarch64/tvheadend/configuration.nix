{ config, pkgs, lib, ... }:

{
  networking.hostName = "tvheadend";
  sound.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  users.users.pulse.extraGroups = [ "lp" ];
  users.users.spotifyd = {
    isNormalUser = true;
    extraGroups = [ "audio" ];
  };

  systemd.services.pulseaudio.wantedBy = [ "multi-user.target" ];

  hardware.pulseaudio = {
    enable = true;
    extraModules = [ pkgs.pulseaudio-modules-bt ];
    systemWide = true;
    extraConfig = ''
      # make bluetooth work?
      load-module module-bluetooth-policy
      load-module module-bluetooth-discover
    '';
  };

  services.spotifyd = {
    enable = true;
    config = ''
      [global]
      username = 1139118329
      password = ${pkgs.secrets.spotify-password}
      device_name = "UE Mobile Boombox"
      initial_volume = 25
      no_audio_cache = true
    '';
  };

  hardware.firmware = [
    pkgs.rtl8723bs_bt
  ];

  systemd.services.connect-speaker = {
    description = "connect speaker";
    script = ''
      ${pkgs.bluez}/bin/bluetoothctl connect 00:0D:44:9D:D4:0F
    '';
    /* wantedBy = [ "multi-user.target" ];
    after = [ "bluetooth.service" ]; */
  };

  systemd.services.enable-bluetooth = {
    description = "enable bluetooth";
    script = ''
      ${pkgs.rtl8723bs_bt}/bin/rtk_hciattach -n -s 115200 /dev/ttyS1 rtk_h5
    '';
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.limit-cpu = {
    description = "limit cpu";
    script = ''
      ${config.boot.kernelPackages.cpupower}/bin/cpupower frequency-set --max 1GHz
    '';
    wantedBy = [ "multi-user.target" ];
  };

  system.build.dtbName = "sun50i-h5-orangepi-prime.dtb";
  hardware.deviceTree = {
    enable = true;
    filter = "*orangepi-prime*";
    overlays = [
      { name = "prime-bt"; dtsFile = "${pkgs.dt-overlays}/orangepi-prime-bt.dts"; }
    ];
  };

  environment.systemPackages = [
    pkgs.rtl8723bs_bt
  ];

  boot.blacklistedKernelModules = [ "drm" "r8723bs" ];
  boot.kernelPackages = pkgs.linuxPackages_allwinner;

  boot.kernelPatches =
    let badPatches = [
      "general-add-overlay-compilation-support"
      "xxx-add-nanopi-r1-and-duo2"
      "general-enable-kernel-dtbs-symbol-generation"
      /* "0001-Revert-leds"
      "0002-Add-leds"
      "board-pine64-add-spi-flash"

      "board-pine-h6" */
      "check"
      "patch-5.8"
      "AC200"
      "tanix"
      /* "ruart-alias" */

      "update-correct-h3-h5-thermal-zones"
      "sun8i-h3-add-overclock-overlays"
      "sun50i-h5-add-gpio-regulator-overclock-overlays"
      "0007-mmc-sunxi-add-support-for-the-MMC-controller"
      "board-h3-nanopi-neo-air"

      "general-fix-builddeb-packaging"
      "general-sunxi-overlays"
      "wifi-"
      "disable-debug-rtl8189fs"
      "disable-debug-rtl8723ds"
      "8723cs"
      "rtl8723bs"

      ".patch.1"
      "-DISABLED"
      ".disabled"
      "-disabled"
      ".patch_broken"
    ];
  in
    (builtins.filter ({ name, ... }: lib.all
      (badPatch: ! lib.hasInfix badPatch name) badPatches
    )
    (lib.mapAttrsToList (name: _: {
        name = "${name}";
        patch = "${pkgs.sources.armbian}/patch/kernel/sunxi-current/${name}";
    })
    (builtins.readDir "${pkgs.sources.armbian}/patch/kernel/sunxi-current")));

  imports = [
    ../common.nix
    ../../../services/tvheadend.nix
  ];

}
