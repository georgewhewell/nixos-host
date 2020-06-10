let
  pkgs = (import <nixpkgs> {
    crossSystem = "aarch64-linux";
  }
  );
  mkCross = name: conf: { ... }: {
    imports = [ conf ./common-cross.nix <nixpkgs/nixos/modules/installer/cd-dvd/sd-image-aarch64.nix> ];
    nixpkgs.crossSystem = pkgs.lib.systems.elaborate "aarch64-linux";
  };
  machines = with pkgs; (import ./aarch64 { inherit lib; });
in
{

  network = {
    inherit pkgs;
    description = "aarch64 cross machines";
  };

} // pkgs.lib.mapAttrs mkCross machines
