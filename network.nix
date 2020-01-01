let
  pkgs = (import <nixpkgs> {
    overlays = [
      (import modules/overlay.nix)
    ];
  });
in {

  network =  {
    inherit pkgs;
    description = "simple hosts";
  };

  "nixhost.lan" = (import ./nixhost.nix);
  "fuckup.lan" = (import ./fuckup.nix);
  "yoga.lan" = (import ./yoga.nix);

}
