let
  pkgs = (import <nixpkgs> {
    crossSystem = "aarch64-linux";
  });
  mkCross = name: conf: { ... }: {
    imports = [ conf ./common-cross.nix ];
  };
  machines = with pkgs; (import ./aarch64 { inherit lib; });
in {

  network =  {
    inherit pkgs;
    description = "aarch64 cross machines";
  };

} // pkgs.lib.mapAttrs mkCross machines
