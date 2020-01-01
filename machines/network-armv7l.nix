let
  pkgs = (import <nixpkgs> {
    system = "armv7l-linux";
  });
  machines = (import ./armv7l { inherit (pkgs) lib; });
in {

  network =  {
    inherit pkgs;
    description = "armv7l native machines";
  };

} // machines
