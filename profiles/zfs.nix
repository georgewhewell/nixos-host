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
      # Preserve the current default explicitly across the upstream default flip.
      forceImportRoot = true;
      requestEncryptionCredentials = false;
    };
  };
}
