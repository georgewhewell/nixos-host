let
  pkgs = (import <nixpkgs> { });
  machines = with pkgs; (import ./x86 { inherit lib; });
in
{

  network = {
    inherit pkgs;
    description = "x86 native machines";
  };

} // machines
