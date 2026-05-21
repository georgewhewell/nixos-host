{
  config,
  lib,
  ...
}: {
  boot.tmp.useTmpfs = lib.mkDefault true;
  nix.settings.trusted-users = ["root" "grw"];
  nix.settings.keep-outputs = true; # Keep build outputs for faster rebuilds

  users.extraUsers.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;
}
