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
    kernelParams = [ "boot.shell_on_fail" "panic=20" ];
    supportedFilesystems = lib.mkForce [ "nfs" ];
    initrd.supportedFilesystems = lib.mkForce [ "ext4" ];
  };

  fileSystems."/var/log" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=16M" ];
  };

  nixpkgs.overlays = [
    (self: super: {
      # broken
      efibootmgr = super.hello;
    })
  ];

  # sometimes fails to build, dont need
  programs.bash.enableCompletion = false;

  # installation-device.nix disables this stuff- re-enable
  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];

  # no documentation :X
  documentation = {
    enable = lib.mkOverride 0 false;
    nixos.enable = lib.mkOverride 0 false;
  };

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

  systemd.services."lights-off" =
    let
      turn-off-leds = pkgs.writeScriptBin "turn-off-leds" ''
        for i in /sys/class/leds/* ; do
          echo 0 > $i/brightness
        done
      '';
    in
    {
      description = "turn off leds";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${turn-off-leds}/bin/turn-off-leds";
      };
    };

  systemd.services."io-is-busy" =
    let
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
    in
    {
      description = "set io_is_busy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${io-is-busy}/bin/io-is-busy";
      };
    };

  boot.kernelPatches = [
    {
      name = "disable-slowthings";
      patch = null;
      extraConfig = ''
        PCI n
        XEN n
        KVM n

        OPENVSWITCH n
        INFINIBAND n
        6LOWPAN n
        CAN n

        ATA n
        SCSI n
        BLK_DEV_DM n

        INPUT_TOUCHSCREEN n

        DRM_PANEL n
        DRM_AMDGPU n
        DRM_RADEON n
        DRM_ETANIV n
        DRM_NOUVEAU n
        DRM_VC4 n
        DRM_MSM n

        AFS_FS n
        ADFS_FS n
        CEPH_FS n
        EROFS_FS n
        UBIFS_FS n
        HFS_FS n
        HFSPLUS_FS n
        AFFS_FS n
        ORANGEFS_FS n
        NTFS_FS n
        NILFS2_FS n
        BTRFS_FS n
        OCFS2_FS n
        GFS2_FS n
        JFS_FS n
        REISERFS_FS n
        ECRYPT_FS n
        VXFS_FS n

        ARCH_MEDIATEK n
        ARCH_BCM2835 n
        ARCH_QCOM n
        ARCH_RENESAS n
        ARCH_TEGRA n
        ARCH_THUNDER n
        ARCH_THUNDER2 n
        ARCH_XGENE n
      '';
    }
    {
      name = "enable-cec";
      patch = null;
      extraConfig = ''
        MEDIA_CEC_SUPPORT y
        MEDIA_CEC_RC y
        DRM_SUN4I_HDMI_CEC y
      '';
    }
    {
      name = "gpio-sysfs";
      patch = null;
      extraConfig = ''
        GPIO_SYSFS y
      '';
    }
    {
      name = "include-symbols";
      patch = pkgs.writeText "include-dts-symbols" ''
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
  ];
}
