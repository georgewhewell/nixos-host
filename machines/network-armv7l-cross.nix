let
  pkgs = (import <nixpkgs> {
    crossSystem = "armv7l-linux";
  });
  mkCross = name: conf: { ... }: {
    imports = [ conf ./common-cross.nix ];
  };
  machines = with pkgs; (import ./armv7l { inherit lib; });
in {

  network =  {
    inherit pkgs;
    description = "armv7l cross machines";
  };

} // pkgs.lib.mapAttrs mkCross machines