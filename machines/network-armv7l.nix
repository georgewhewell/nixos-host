
let
  pkgs = (import <nixpkgs> {
    system = "armv7l-linux";
  });
  mkNative = name: conf: { ... }: {
    imports = [ conf ];
    nixpkgs.localSystem = pkgs.lib.systems.elaborate "armv7l-linux";
  };
  machines = (import ./armv7l { inherit (pkgs) lib; });
in {

  network =  {
    inherit pkgs;
    description = "armv7l native machines";
  };

} // pkgs.lib.mapAttrs mkNative machines
