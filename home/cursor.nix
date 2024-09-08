{ config, lib, pkgs, ... }:

{
  home.pointerCursor = {
    gtk. enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 16;
  };
}
