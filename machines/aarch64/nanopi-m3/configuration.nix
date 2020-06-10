{ config, pkgs, lib, ... }:

{

  networking.hostName = "nanopi-m3";

  boot.kernelParams = [
    "ignore_loglevel"
    "boot.shell_on_fail"
    "earlyprintk"
    "console=ttySAC0,115200"
  ];

  # stop kernel build OOM
  nix.buildCores = 7;

  boot.kernelPackages =
    with pkgs; recurseIntoAttrs (linuxPackagesFor (
      buildLinux ({
    version = "4.14";
    modDirVersion = "4.14.137";
    defconfig = "nanopim3_defconfig";

    src = pkgs.sources.linux_nanopi_m3;

    inherit (pkgs) buildPackages stdenv;

    kernelPatches = [
      {
        name = "revert cross compile";
        patch = ./revert-cross-compile.patch;
      }
    {
      name = "export-func";
      patch = ./export-func.patch;
      extraConfig = ''
        INPUT_TOUCHSCREEN n
        WLAN n
        BT n
        DM_RAID n
        MD n
        NF_TABLES_IPV4 m
        IPV6 n
        CRAMFS_FS n
        XEN n
        VFIO n
        WIRELESS n
        WIRELESS_EXT n
        MEDIA_SUPPORT n
        STAGING n
        FPGA n
        PCI n
        DRM n
        MALI400 n
        NILFS2_FS n
        BTRFS_FS n
        HPFS_FS n
        GFS2_FS n
        OCFS2_FS n
        REISERFS_FS n
        UFS_FS n
        XFS_FS n
        CIFS n
        EFI n
        INPUT n
        NFC n
        HID n
        USB_HID n
        I2C_HID n
        HAVE_PERF_EVENTS n
        PERF_EVENTS n
        JFS_FS n
        JFFS2_FS n
        NCPFS_FS n
        9P_FS n
        NET_9P n
        HFS_FS n
        HFSPLUS_FS n
        F2FS_FS n
        CEPH_FS n
        VIDEO_DEV n
        INFINIBAND n
        SOUND n
      '';
    }];
  })));

  imports = [
    ../common.nix
  ];

}
