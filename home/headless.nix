{ config, lib, pkgs, ... }:

{
  services.gpg-agent.enable = lib.mkForce false;
}
