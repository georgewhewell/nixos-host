{ config, lib, pkgs, ... }:

{

  # libp11 fails to compile
  security.rngd.enable = lib.mkForce false;
  security.polkit.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; lib.mkForce [ bash ];

  # faster kernel builds
  boot.kernelPatches = [
  {
    name = "disable-crap";
    patch = null;
    extraConfig = ''
      INPUT_TOUCHSCREEN n
      WLAN n
      BT n
      DM_RAID n
      MD n
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

  imports = [
    ../common-arm.nix
    ../../services/buildfarm.nix
    <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-armv7l-multiplatform.nix>
  ];
}
