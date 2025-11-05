{
  config,
  pkgs,
  lib,
  ...
}: {
  boot = {
    supportedFilesystems = ["zfs"];
    zfs = {
      package = pkgs.zfs_unstable;
      requestEncryptionCredentials = false;
    };
  };
}
