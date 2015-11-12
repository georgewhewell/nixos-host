{ config, lib, pkgs, ... }:

{
  # Use the gummiboot efi boot loader.
  boot.loader.gummiboot.enable = true;
  boot.loader.gummiboot.timeout = 1;
  boot.loader.efi.canTouchEfiVariables = true;
}
