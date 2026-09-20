{
  config,
  lib,
  pkgs,
  ...
}: {
  # tmp
  boot.tmp.useTmpfs = true;

  # 1MB journal
  services.journald = {
    settings.Journal = {
      Storage = "volatile";
      RuntimeMaxUse = "1M";
      RuntimeMaxFileSize = "256K";
      SystemMaxUse = "1M";
      SystemMaxFileSize = "256K";
    };
  };
}
