{ config, pkgs, ... }:

{
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    sshKeys = [ "EEB6A2D42BF04599AFEF0E9C104AB9B2E16AE31D" ];
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  programs.ssh =
    {
      extraConfig = ''
        Host *.satanic.link
          RemoteForward /run/user/1000/gnupg/S.gpg-agent /run/user/1000/gnupg/S.gpg-agent.extra
          RemoteForward /run/user/1000/gnupg/S.gpg-agent.ssh /run/user/1000/gnupg/S.gpg-agent.ssh
      '';
    };

  services.keybase.enable = true;
  services.kbfs.enable = true;

  home.packages = [ pkgs.pinentry-curses ];

}
