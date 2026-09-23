# Evaluate a Windows host description (see module.nix) into
# `{ config, ... }`, mirroring nixosSystem's shape so the flake can expose
# windowsConfigurations.<name>.config.build.{state,bundle,deploy}.
{
  lib,
  pkgs,
  specialArgs ? {},
}: name: machine:
lib.evalModules {
  modules = [
    ./module.nix
    machine
    {
      inherit name;
      _module.args.pkgs = pkgs;
    }
  ];
  inherit specialArgs;
}
