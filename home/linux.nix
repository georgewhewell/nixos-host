{ pkgs, config, ... }:

{
  xdg.enable = true;
  services.lorri.enable = true;

  programs.gpg = {
    enable = true;
  };

}
