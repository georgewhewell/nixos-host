let
  pkgs = (import <nixpkgs> {
    system = "aarch64-linux";
  }
  );
  mkNative = name: conf: { ... }: {
    imports = [ conf <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix> <home-manager/nixos> ];
    nixpkgs.localSystem = pkgs.lib.systems.elaborate "aarch64-linux";
  };
  machines = with pkgs; (import ./aarch64 { inherit lib; });
in
{

  network = {
    inherit pkgs;
    description = "aarch64 native machines";
  };

} // pkgs.lib.mapAttrs mkNative machines
