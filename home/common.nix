{ pkgs, config, ... }:

{

  imports = [
    ./i3.nix
    ./alacritty.nix
    ./polybar.nix
    ./rofi.nix
    ./vim.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    exa
    ripgrep
  ];

}
