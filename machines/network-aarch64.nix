let
  pkgs = (import <nixpkgs> {
    system = "aarch64-linux";
  });
  mkNative = name: conf: { ... }: {
    imports = [ conf ];
    nixpkgs.localSystem = pkgs.lib.systems.elaborate "aarch64-linux";
  };
  machines = with pkgs; (import ./aarch64 { inherit lib; });
in {

  network =  {
    inherit pkgs;
    description = "aarch64 native machines";
  };

} // pkgs.lib.mapAttrs mkNative machines
