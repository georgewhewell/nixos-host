{
  config,
  pkgs,
  lib,
  ...
}: {
  boot = {
    supportedFilesystems = ["zfs"];
    zfs = {
      # Use the ZFS userspace package from pkgs. Our overlay pins it to
      # OpenZFS upstream, and NixOS will select the matching kernel module
      # via linuxPackages.${pkgs.zfs.kernelModuleAttribute}.
      package = config.boot.kernelPackages.zfs_unstable;
      requestEncryptionCredentials = false;
    };
  };
}
