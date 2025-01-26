{
  config,
  lib,
  pkgs,
  ...
}: {
  nix.settings.trusted-users = ["root" "grw"];

  users.extraUsers.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;
}
