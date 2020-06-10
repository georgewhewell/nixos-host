{ config, pkgs, lib, ... }:

{

  imports = [
    ../profiles/common.nix
    ../profiles/home.nix
    ../services/buildfarm-slave.nix
    <nixpkgs/nixos/modules/profiles/minimal.nix>
  ];

  boot = {
    cleanTmpDir = true;
    kernelParams = [ "boot.shell_on_fail" "panic=20"];
    supportedFilesystems = lib.mkForce [ "nfs" ];
    initrd.supportedFilesystems = lib.mkForce [ "ext4" ];
  };

  # sometimes fails to build, dont need
  programs.bash.enableCompletion = false;

  # installation-device.nix disables this stuff- re-enable
  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];

  # no documentation :X
  documentation = {
    enable = lib.mkOverride 0 false;
    nixos = lib.mkOverride 0 false;
  };

  services.nixosManual.showManual = lib.mkForce false;
  services.xserver.enable = lib.mkDefault false;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  fileSystems."/".options = [
    "relatime"
  ];

  powerManagement.enable = lib.mkDefault true;
  powerManagement.cpuFreqGovernor = "ondemand";

  nix.gc = {
    automatic = true;
    dates = "daily";
  };

  systemd.services."lights-off" = let
    turn-off-leds = pkgs.writeScriptBin "turn-off-leds" ''
      for i in /sys/class/leds/* ; do
        echo 0 > $i/brightness
      done
    '';
    in {
      description = "turn off leds";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${turn-off-leds}/bin/turn-off-leds";
      };
  };

  systemd.services."io-is-busy" = let
    io-is-busy = pkgs.writeScriptBin "io-is-busy" ''
      cd /sys/devices/system/cpu
      for i in cpufreq/ondemand cpu0/cpufreq/ondemand cpu4/cpufreq/ondemand ; do
        if [ -d $i ]; then
          echo 1  >$i/io_is_busy
          echo 25 >$i/up_threshold
          echo 10 >$i/sampling_down_factor
        fi
      done
    '';
    in {
      description = "set io_is_busy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${io-is-busy}/bin/io-is-busy";
      };
  };

  boot.kernelPatches = [
    { name = "enable-cec";
      patch = null;
      extraConfig = ''
        MEDIA_CEC_SUPPORT y
        MEDIA_CEC_RC y
        DRM_SUN4I_HDMI_CEC y
        FB_SUN5I_EINK n
      '';
    }
    {
      name = "include-symbols";
      patch = pkgs.writeText "the_patch" ''
        diff --git a/scripts/Makefile.lib b/scripts/Makefile.lib
        index 97547108ee7f..436e60b97264 100644
        --- a/scripts/Makefile.lib
        +++ b/scripts/Makefile.lib
        @@ -264,7 +264,7 @@ DTC_FLAGS += -Wnode_name_chars_strict \
                -Wproperty_name_chars_strict
         endif

        -DTC_FLAGS += $(DTC_FLAGS_$(basetarget))
        +DTC_FLAGS += $(DTC_FLAGS_$(basetarget)) -@
      '';
    }
    {
      # uboot should be setting this properly but..
      name = "fix odroid-hc1 dts name";
      patch = pkgs.writeText "patch" ''
        diff --git a/arch/arm/boot/dts/Makefile b/arch/arm/boot/dts/Makefile
        index e8dd99201397..142e5a28783c 100644
        --- a/arch/arm/boot/dts/Makefile
        +++ b/arch/arm/boot/dts/Makefile
        @@ -208,7 +208,7 @@ dtb-$(CONFIG_ARCH_EXYNOS5) += \
          exynos5420-arndale-octa.dtb \
          exynos5420-peach-pit.dtb \
          exynos5420-smdk5420.dtb \
        -	exynos5422-odroidhc1.dtb \
        +	exynos5422-odroid.dtb \
          exynos5422-odroidxu3.dtb \
          exynos5422-odroidxu3-lite.dtb \
          exynos5422-odroidxu4.dtb \
        diff --git a/arch/arm/boot/dts/exynos5422-odroidhc1.dts b/arch/arm/boot/dts/exynos5422-odroid.dts
        similarity index 100%
        rename from arch/arm/boot/dts/exynos5422-odroidhc1.dts
        rename to arch/arm/boot/dts/exynos5422-odroid.dts
      '';
    }
  ];
}
