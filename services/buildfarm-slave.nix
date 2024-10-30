{ config, lib, pkgs, ... }:

{
  nix.settings.trusted-users = [ "grw" ];

  users.extraUsers.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;
}
