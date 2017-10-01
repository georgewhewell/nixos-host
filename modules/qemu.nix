{ profile, system ? builtins.currentSystem }:

let
  loadcfg = cfgfile: { config, pkgs, ...}: {
    imports = [
      cfgfile
      ../profiles/common.nix
      <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
    ];
    config = {
      virtualisation = {};
    };
  };
  mkcfg = cfgfile:
    import <nixpkgs/nixos/lib/eval-config.nix> {
      inherit system;
      modules = [ (loadcfg cfgfile) ];
    };
in (mkcfg profile).config.system.build.vm
