{ pkgs, config, ... }:

{

  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    pinentryFlavor = "curses";
  };

  services.keybase.enable = true;
  services.kbfs.enable = true;

}
