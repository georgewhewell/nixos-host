{ config, lib, pkgs, ... }:

{
  # Save this file!
  system.copySystemConfiguration = true;

  # The NixOS release to be compatible with for stateful data such as databases.
  system.stateVersion = "16.03";
}
