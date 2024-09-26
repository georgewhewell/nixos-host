{ config, lib, pkgs, ... }:

{
  users.extraUsers.root.openssh.authorizedKeys.keys =
    config.users.users.grw.openssh.authorizedKeys.keys;
}
