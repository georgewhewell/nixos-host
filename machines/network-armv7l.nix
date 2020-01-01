let
  pkgs = (import <nixpkgs> {
    system = "armv7l-linux";
  });
in {

  network =  {
    inherit pkgs;
    description = "armv7l native machines";
  };

  odroid-hc1 = (import ./armv7l/odroid-hc1.nix);
  bananapi-m3 = (import ./armv7l/bananapi-m3.nix);

}
