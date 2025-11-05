{
  config,
  lib,
  ...
}: {
  boot.tmp.useTmpfs = lib.mkDefault true;

  nix.settings.trusted-users = ["root" "grw"];

  users.extraUsers.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;
}
