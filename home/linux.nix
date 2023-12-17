{ pkgs, config, ... }:

{
  xdg.enable = true;
  services.lorri.enable = true;

  programs.gpg = {
    enable = true;
  };

  home.packages = with pkgs; [
    ccid
    yubikey-manager
    opensc
    pcsctools
  ];
}
