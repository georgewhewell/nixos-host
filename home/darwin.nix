{ config, pkgs, ... }:

{
  # replace crappy mac utils
  home.packages = with pkgs; [
    gnused
    coreutils
    openvpn
    yt-dlp
  ];

  # darwin-specific overlays
  nixpkgs.overlays = [
    (self: super: {

      # some error building
      vim_configurable = super.vim_configurable.override {
        guiSupport = "no";
      };
    })
  ];

}
